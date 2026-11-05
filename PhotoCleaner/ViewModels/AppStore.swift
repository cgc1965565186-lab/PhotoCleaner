import AVFoundation
import Foundation
import Network
import Observation
import Photos
import SwiftData
import UIKit

@MainActor
@Observable
final class AppStore: NSObject, PHPhotoLibraryChangeObserver {
    private static let scanCompletionKey = "app.codex.jingyu.scan-complete"

    var selectedTab = 0
    var records: [MediaRecord] = []
    var duplicateGroups: [DuplicateGroup] = []
    var filters = LibraryFilters()
    var selectedIdentifiers = Set<String>()
    var storage = StorageSnapshot(totalBytes: nil, availableBytes: nil)
    var isScanning = false
    var scanProgress = 0.0
    var statusMessage = ""
    var alertMessage: String?
    var showsScanConfirmation = false
    var showsCellularConfirmation = false
    var hasLimitedAccess = false
    var hasPhotoAccess = false
    var isScanComplete = UserDefaults.standard.bool(forKey: AppStore.scanCompletionKey)
    var lastScanDate: Date?

    private(set) var libraryStats = LibraryStats()
    /// 全量记录索引：O(1) 按 ID 查找，避免视图渲染路径上的线性扫描。
    private(set) var recordsByID: [String: MediaRecord] = [:]
    /// 按类别预分组的重复组。
    private(set) var groupsByKind: [DuplicateKind: [DuplicateGroup]] = [:]
    /// 选择集摘要：数量、字节数、未知大小项数，随选择变化增量维护。
    private(set) var selectionSummary = SelectionSummary()

    private let library = PhotoLibraryService()
    @ObservationIgnored private let networkMonitor = NWPathMonitor()
    @ObservationIgnored private var cellularState: Bool?
    @ObservationIgnored private var cellularWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var indexEntriesByID: [String: AssetIndexEntry] = [:]
    @ObservationIgnored private var libraryChangedWhileScanning = false
    private var modelContext: ModelContext?
    private var scanTask: Task<Void, Never>?

    override init() {
        super.init()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let usesCellular = path.usesInterfaceType(.cellular)
            Task { @MainActor [weak self] in
                guard let self else { return }
                cellularState = usesCellular
                cellularWaiter?.resume(returning: usesCellular)
                cellularWaiter = nil
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "app.codex.jingyu.network"))
    }

    // MARK: - 派生数据

    var selectedEstimatedBytes: Int64 { selectionSummary.bytes }

    var selectedUnknownSizeCount: Int { selectionSummary.unknownCount }

    var unknownSizeCount: Int { libraryStats.unknownSizeCount }

    func groups(for kind: DuplicateKind) -> [DuplicateGroup] {
        groupsByKind[kind] ?? []
    }

    func record(with identifier: String) -> MediaRecord? {
        recordsByID[identifier]
    }

    /// 详情页大图，按屏幕分辨率请求。
    func detailImage(for asset: PHAsset) async -> UIImage? {
        let scale = max(UIScreen.main.scale, 2)
        let bounds = UIScreen.main.bounds.size
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return await library.thumbnail(for: asset, targetSize: pixelSize, networkAllowed: true)
    }

    /// 详情页视频播放资源。
    func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        await library.playerItem(for: asset, networkAllowed: true)
    }

    // MARK: - 生命周期

    func configure(with context: ModelContext) async {
        modelContext = context
        refreshStorage()
        let status = library.authorizationStatus()
        hasPhotoAccess = status == .authorized || status == .limited
        hasLimitedAccess = status == .limited
        guard hasPhotoAccess else {
            if status == .denied || status == .restricted { removeAllCachedEntries() }
            return
        }
        restoreCache()
        if hasLimitedAccess { reconcileAccessibleRecords() }
        PHPhotoLibrary.shared().register(self)
    }

    // MARK: - 扫描入口

    func requestScan() {
        showsScanConfirmation = true
    }

    func startScan() {
        showsScanConfirmation = false
        prepareScan()
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func continueOnCellular() {
        showsCellularConfirmation = false
        launchScan()
    }

    func cancelCellularOperation() {
        showsCellularConfirmation = false
        statusMessage = "已取消蜂窝网络读取。"
    }

    private func prepareScan() {
        Task {
            guard await usesCellularNetwork() else {
                launchScan()
                return
            }
            switch CellularPolicy.current {
            case .ask:
                showsCellularConfirmation = true
            case .wifiOnly:
                alertMessage = "当前使用蜂窝网络，按你的设置已跳过读取。连接 Wi-Fi 后再开始扫描。"
            }
        }
    }

    private func launchScan() {
        guard !isScanning else {
            alertMessage = "当前扫描尚未完成，请先等待或取消后再开始。"
            return
        }
        scanTask?.cancel()
        scanTask = Task { await performScan() }
    }

    private func usesCellularNetwork() async -> Bool {
        if let cellularState { return cellularState }
        return await withCheckedContinuation { cellularWaiter = $0 }
    }

    // MARK: - 删除

    func requestDelete() {
        guard !selectedIdentifiers.isEmpty else { return }
        showsDeleteConfirmation = true
    }

    var showsDeleteConfirmation = false

    func deleteSelected() {
        showsDeleteConfirmation = false
        let identifiers = Array(selectedIdentifiers)
        let selectedIDs = Set(identifiers)
        Task {
            do {
                try await library.deleteAssets(identifiers: identifiers)
                applyRecords(records.filter { !selectedIDs.contains($0.id) })
                let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
                setGroups(duplicateGroups.compactMap { group in
                    let remainingIDs = group.assetIDs.filter { !selectedIDs.contains($0) }
                    guard remainingIDs.count > 1 else { return nil }
                    let keeper = group.recommendedKeeperID.flatMap { selectedIDs.contains($0) ? nil : $0 }
                        ?? recommendedKeeper(in: remainingIDs, recordByID: recordByID)
                    return DuplicateGroup(
                        id: group.id,
                        assetIDs: remainingIDs,
                        kind: group.kind,
                        recommendedKeeperID: keeper
                    )
                })
                for identifier in selectedIDs {
                    if let entry = indexEntriesByID.removeValue(forKey: identifier) {
                        modelContext?.delete(entry)
                    }
                }
                saveCache()
                selectedIdentifiers.subtract(selectedIDs)
                refreshSelectionSummary()
                refreshStorage()
                alertMessage = "已提交删除请求。项目可能仍在“最近删除”中，并会按 iCloud 照片设置同步。"
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func toggleSelection(for record: MediaRecord) {
        if selectedIdentifiers.contains(record.id) {
            selectedIdentifiers.remove(record.id)
        } else {
            selectedIdentifiers.insert(record.id)
        }
        refreshSelectionSummary()
    }

    /// 一键选中组内除建议保留项之外的全部成员。
    func selectAllExceptRecommended(in group: DuplicateGroup) {
        for identifier in group.assetIDs where identifier != group.recommendedKeeperID {
            selectedIdentifiers.insert(identifier)
        }
        refreshSelectionSummary()
    }

    func clearSelection() {
        guard !selectedIdentifiers.isEmpty else { return }
        selectedIdentifiers.removeAll()
        refreshSelectionSummary()
    }

    // MARK: - 其他

    func refreshStorage() {
        storage = StorageService.snapshot()
    }

    func refreshAuthorization() {
        let status = library.authorizationStatus()
        hasPhotoAccess = status == .authorized || status == .limited
        hasLimitedAccess = status == .limited
        if status == .denied || status == .restricted {
            scanTask?.cancel()
            applyRecords([])
            setGroups([])
            selectedIdentifiers.removeAll()
            setScanComplete(false)
            removeAllCachedEntries()
            statusMessage = "照片访问权限已关闭；本地索引已清除。"
        }
    }

    func refreshLibraryAccess() {
        refreshAuthorization()
        if hasLimitedAccess && !isScanning {
            reconcileAccessibleRecords()
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func clearLocalCache() {
        guard let modelContext else { return }
        do {
            let entries = try modelContext.fetch(FetchDescriptor<AssetIndexEntry>())
            for entry in entries { modelContext.delete(entry) }
            try modelContext.save()
            indexEntriesByID.removeAll()
            setScanComplete(false)
            alertMessage = "已清除 \(entries.count) 条本地扫描索引。照片和视频没有被修改。"
        } catch {
            alertMessage = "暂时无法清除本地索引。"
        }
    }

    /// 当前本地索引条目数。
    var indexEntryCount: Int { indexEntriesByID.count }

    /// 灵敏度变更后用现有指纹立即重建分组，无需重新扫描。
    func rebuildGroupsFromCache() {
        guard !isScanning, !records.isEmpty else { return }
        setGroups(makeCachedGroups(from: records))
    }

    /// 导出当前重复分组清单为 CSV 文本（含 UTF-8 BOM，方便 Excel 直接打开）。
    func duplicateExportText() -> String {
        var lines = ["分组类型,组内序号,建议保留,媒体类型,拍摄时间,分辨率,时长(秒),文件大小(字节),媒体ID"]
        let formatter = ISO8601DateFormatter()
        for group in duplicateGroups {
            for (index, identifier) in group.assetIDs.enumerated() {
                guard let record = record(with: identifier) else { continue }
                let keeper = identifier == group.recommendedKeeperID ? "是" : ""
                let created = record.creationDate.map { formatter.string(from: $0) } ?? ""
                let duration = record.kind == .video ? String(format: "%.0f", record.duration) : ""
                let fields = [
                    group.kind.title,
                    "\(index + 1)",
                    keeper,
                    record.kind.title,
                    created,
                    "\(record.width)x\(record.height)",
                    duration,
                    record.byteSize.map(String.init) ?? "",
                    record.id
                ]
                lines.append(fields.joined(separator: ","))
            }
        }
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            refreshStorage()
            refreshAuthorization()
            if hasPhotoAccess { setScanComplete(false) }
            if isScanning { libraryChangedWhileScanning = true }
        }
    }

    // MARK: - 扫描主流程

    private func performScan() async {
        guard !isScanning else { return }
        isScanning = true
        setScanComplete(false)
        scanProgress = 0
        statusMessage = "正在读取照片图库…"
        defer {
            library.stopCachingThumbnails()
            isScanning = false
        }

        var status = library.authorizationStatus()
        if status == .notDetermined {
            status = await library.requestAuthorization()
        }
        guard status == .authorized || status == .limited else {
            hasPhotoAccess = false
            hasLimitedAccess = false
            alertMessage = status == .restricted
                ? "此设备限制了照片访问权限。"
                : "需要照片图库访问权限才能扫描。你可以在系统设置中更改权限。"
            return
        }

        hasPhotoAccess = true
        hasLimitedAccess = status == .limited
        let assets = library.fetchAssets()
        guard !assets.isEmpty else {
            applyRecords([])
            setGroups([])
            lastScanDate = .now
            scanProgress = 1
            setScanComplete(true)
            statusMessage = status == .limited ? "当前授权范围内没有照片。" : "照片图库为空。"
            return
        }

        let cachedEntries = loadCache()

        // 阶段 1：后台构建基础记录（不读取任何媒体数据）。
        statusMessage = "正在建立媒体清单…"
        let service = library
        var scanned = await Task.detached(priority: .userInitiated) { [cachedEntries] () -> [MediaRecord] in
            assets.map { asset in Self.baseRecord(for: asset, cached: cachedEntries[asset.localIdentifier]) }
        }.value
        guard !Task.isCancelled else {
            statusMessage = "扫描已暂停；再次扫描时会复用已完成的指纹。"
            return
        }
        scanProgress = 0.05

        // 阶段 2：并发计算照片感知指纹（后台，4 路）。
        let fingerprints = await computeFingerprints(for: scanned, service: service)
        guard !Task.isCancelled else {
            persistBatch(scanned)
            statusMessage = "扫描已暂停；再次扫描时会复用已完成的指纹。"
            return
        }
        applyFingerprints(fingerprints, to: &scanned)

        // 阶段 3：后台读取资源元数据大小（零媒体读取）。
        statusMessage = "正在读取资源大小…"
        await fillResourceSizes(into: &scanned, service: service)
        guard !Task.isCancelled else {
            persistBatch(scanned)
            statusMessage = "扫描已暂停；再次扫描时会复用已完成的指纹。"
            return
        }

        // 阶段 4：后台查重分组。
        statusMessage = "正在整理相似照片与连拍…"
        applyRecords(scanned)
        setGroups(await buildDuplicateGroups(from: scanned))
        guard !Task.isCancelled else {
            persistBatch(scanned)
            statusMessage = "扫描已暂停；已保留本次结果。"
            return
        }

        persistBatch(scanned)
        let changedDuringScan = libraryChangedWhileScanning
        if changedDuringScan {
            libraryChangedWhileScanning = false
            reconcileAccessibleRecords()
        }
        lastScanDate = .now
        scanProgress = 1
        setScanComplete(!changedDuringScan)
        statusMessage = changedDuringScan
            ? "扫描期间图库发生变化，建议重新扫描。"
            : (hasLimitedAccess ? "扫描完成 · 结果仅包含你授权的照片" : "扫描完成")
        refreshStorage()
    }

    private func computeFingerprints(
        for scanned: [MediaRecord],
        service: PhotoLibraryService
    ) async -> [String: ImageFingerprint] {
        let pending = scanned.filter { $0.kind == .photo && $0.fingerprint == nil }
        guard !pending.isEmpty else { return [:] }

        statusMessage = "正在分析照片缩略图…"
        var result: [String: ImageFingerprint] = [:]
        result.reserveCapacity(pending.count)
        let total = max(pending.count, 1)
        var completed = 0
        var reportedPercent = -1

        await withTaskGroup(of: (String, ImageFingerprint?).self) { group in
            var iterator = pending.makeIterator()
            let concurrency = 4

            func enqueueNext() {
                if let record = iterator.next() {
                    group.addTask {
                        await Self.fingerprint(for: record, service: service)
                    }
                }
            }

            for _ in 0..<concurrency { enqueueNext() }
            for await (identifier, fingerprint) in group {
                if Task.isCancelled { group.cancelAll() }
                completed += 1
                if let fingerprint { result[identifier] = fingerprint }

                let percent = Int(45.0 * Double(completed) / Double(total))
                if percent > reportedPercent {
                    reportedPercent = percent
                    scanProgress = 0.05 + Double(percent) / 100.0
                }
                enqueueNext()
            }
        }
        return result
    }

    private func fillResourceSizes(into scanned: inout [MediaRecord], service: PhotoLibraryService) async {
        let pendingIndices = scanned.indices.filter { scanned[$0].byteSize == nil }
        guard !pendingIndices.isEmpty else { return }

        let total = max(pendingIndices.count, 1)
        var completed = 0
        var reportedPercent = -1

        await withTaskGroup(of: (Int, Int64?).self) { group in
            var iterator = pendingIndices.makeIterator()
            let concurrency = 4

            func enqueueNext() {
                if let index = iterator.next() {
                    let asset = scanned[index].asset
                    group.addTask {
                        (index, service.resourceSummary(for: asset).byteSize)
                    }
                }
            }

            for _ in 0..<concurrency { enqueueNext() }
            for await (index, byteSize) in group {
                if Task.isCancelled { group.cancelAll() }
                completed += 1
                if let byteSize {
                    scanned[index].byteSize = byteSize
                    scanned[index].digest = DigestFingerprint.make(
                        byteSize: byteSize,
                        width: scanned[index].width,
                        height: scanned[index].height,
                        differenceHash: scanned[index].fingerprint?.differenceHash
                    )
                }

                let percent = Int(25.0 * Double(completed) / Double(total))
                if percent > reportedPercent {
                    reportedPercent = percent
                    scanProgress = 0.5 + Double(percent) / 100.0
                }
                enqueueNext()
            }
        }
    }

    private func buildDuplicateGroups(from scanned: [MediaRecord]) async -> [DuplicateGroup] {
        let candidates: [FingerprintedAsset] = scanned.compactMap { record in
            guard record.kind == .photo, let fingerprint = record.fingerprint else { return nil }
            return FingerprintedAsset(id: record.id, fingerprint: fingerprint)
        }
        let sensitivity = ScanSensitivity.current
        let visualCandidates = await Task.detached(priority: .userInitiated) {
            DuplicateGrouper.groups(
                from: candidates,
                hammingThreshold: sensitivity.hammingThreshold,
                colorThreshold: sensitivity.colorThreshold
            )
        }.value

        let recordByID = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(visualCandidates.count)
        for ids in visualCandidates {
            // 完全重复：字节数、像素尺寸与感知哈希全部一致（不读取媒体内容）。
            let exactBuckets = Dictionary(grouping: ids.compactMap { id -> (String, String)? in
                guard let record = recordByID[id], let digest = record.digest else { return nil }
                return (digest, id)
            }, by: { $0.0 })

            for bucket in exactBuckets.values where bucket.count > 1 {
                let memberIDs = bucket.map(\.1).sorted()
                groups.append(DuplicateGroup(
                    id: "exact-\(memberIDs[0])",
                    assetIDs: memberIDs,
                    kind: .exact,
                    recommendedKeeperID: recommendedKeeper(in: memberIDs, recordByID: recordByID)
                ))
            }

            let exactMemberIDs = Set(exactBuckets.values.filter { $0.count > 1 }.flatMap { $0.map(\.1) })
            let remaining = ids.filter { !exactMemberIDs.contains($0) }
            if remaining.count > 1 {
                // 全部成员属于同一次连拍时交给连拍清单，避免重复呈现。
                let burstIDs = Set(remaining.compactMap { recordByID[$0]?.burstIdentifier })
                if burstIDs.count > 1 || burstIDs.isEmpty {
                    groups.append(DuplicateGroup(
                        id: "similar-\(remaining[0])",
                        assetIDs: remaining,
                        kind: .similar,
                        recommendedKeeperID: recommendedKeeper(in: remaining, recordByID: recordByID)
                    ))
                }
            }
        }

        let burstBuckets = Dictionary(grouping: scanned.compactMap { record -> (String, String)? in
            guard let burst = record.burstIdentifier else { return nil }
            return (burst, record.id)
        }, by: \.0)
        for bucket in burstBuckets.values where bucket.count > 1 {
            let memberIDs = bucket.map(\.1).sorted()
            groups.append(DuplicateGroup(
                id: "burst-\(memberIDs[0])",
                assetIDs: memberIDs,
                kind: .burst,
                recommendedKeeperID: recommendedKeeper(in: memberIDs, recordByID: recordByID)
            ))
        }

        return groups.sorted { $0.id < $1.id }
    }

    nonisolated private static func fingerprint(
        for record: MediaRecord,
        service: PhotoLibraryService
    ) async -> (String, ImageFingerprint?) {
        let image = await service.thumbnail(
            for: record.asset,
            targetSize: CGSize(width: 192, height: 192),
            networkAllowed: true
        )
        guard let cgImage = image?.cgImage else { return (record.id, nil) }
        return (record.id, PerceptualHasher.fingerprint(cgImage))
    }

    nonisolated private static func baseRecord(
        for asset: PHAsset,
        cached: AssetIndexEntry?
    ) -> MediaRecord {
        let fingerprint: ImageFingerprint?
        if let hashValue = cached?.perceptualHash {
            fingerprint = ImageFingerprint(
                differenceHash: UInt64(bitPattern: hashValue),
                red: UInt8(clamping: cached?.averageRed ?? 0),
                green: UInt8(clamping: cached?.averageGreen ?? 0),
                blue: UInt8(clamping: cached?.averageBlue ?? 0)
            )
        } else {
            fingerprint = nil
        }
        return MediaRecord(
            asset: asset,
            byteSize: cached?.byteSize,
            fingerprint: fingerprint,
            digest: cached?.digest
        )
    }

    private func applyFingerprints(_ fingerprints: [String: ImageFingerprint], to scanned: inout [MediaRecord]) {
        guard !fingerprints.isEmpty else { return }
        for index in scanned.indices {
            if let fingerprint = fingerprints[scanned[index].id] {
                scanned[index].fingerprint = fingerprint
                scanned[index].digest = DigestFingerprint.make(
                    byteSize: scanned[index].byteSize,
                    width: scanned[index].width,
                    height: scanned[index].height,
                    differenceHash: fingerprint.differenceHash
                )
            }
        }
    }

    // MARK: - 记录与缓存

    private func applyRecords(_ newRecords: [MediaRecord]) {
        records = newRecords
        recordsByID = Dictionary(uniqueKeysWithValues: newRecords.map { ($0.id, $0) })
        libraryStats = LibraryStats(records: newRecords)
        refreshSelectionSummary()
    }

    private func setGroups(_ newGroups: [DuplicateGroup]) {
        duplicateGroups = newGroups
        groupsByKind = Dictionary(grouping: newGroups, by: \.kind)
    }

    private func refreshSelectionSummary() {
        var count = 0
        var bytes: Int64 = 0
        var unknown = 0
        for identifier in selectedIdentifiers {
            guard let record = recordsByID[identifier] else { continue }
            count += 1
            if let size = record.byteSize {
                bytes += size
            } else {
                unknown += 1
            }
        }
        selectionSummary = SelectionSummary(count: count, bytes: bytes, unknownCount: unknown)
    }

    private func recommendedKeeper(in identifiers: [String], recordByID: [String: MediaRecord]) -> String? {
        identifiers.compactMap { recordByID[$0] }
            .max { lhs, rhs in
                let leftScore = (lhs.isFavorite ? 1_000_000_000 : 0) + lhs.width * lhs.height
                let rightScore = (rhs.isFavorite ? 1_000_000_000 : 0) + rhs.width * rhs.height
                return leftScore < rightScore
            }?.id
    }

    private func restoreCache() {
        guard let modelContext else { return }
        do {
            let entries = try modelContext.fetch(FetchDescriptor<AssetIndexEntry>())
            indexEntriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.localIdentifier, $0) })
            let assets = entries.isEmpty ? [] : library.fetchAssets(identifiers: entries.map(\.localIdentifier))
            let currentCount = library.assetCount()
            let isComplete = UserDefaults.standard.bool(forKey: Self.scanCompletionKey)
                && entries.count == currentCount
                && assets.count == currentCount
            setScanComplete(isComplete)
            let accessibleIDs = Set(assets.map(\.localIdentifier))
            let staleIDs = indexEntriesByID.keys.filter { !accessibleIDs.contains($0) }
            for identifier in staleIDs {
                if let entry = indexEntriesByID.removeValue(forKey: identifier) {
                    modelContext.delete(entry)
                }
            }
            guard !entries.isEmpty else {
                statusMessage = currentCount > 0
                    ? "图库已连接；开始扫描以建立本地索引。"
                    : (isScanComplete ? "照片图库为空。" : "")
                return
            }
            let restored = assets.map { Self.baseRecord(for: $0, cached: indexEntriesByID[$0.localIdentifier]) }
            applyRecords(restored)
            setGroups(makeCachedGroups(from: restored))
            lastScanDate = entries.map(\.updatedAt).max()
            statusMessage = records.isEmpty && currentCount == 0
                ? "照片图库为空。"
                : (isScanComplete ? "已载入上次扫描结果。" : "上次扫描未完成；再次扫描会继续补齐图库。")
            saveCache()
        } catch {
            statusMessage = "本地扫描索引无法读取，将在下次扫描时重建。"
        }
    }

    private func reconcileAccessibleRecords() {
        let assets = library.fetchAssets()
        let accessibleIDs = Set(assets.map(\.localIdentifier))
        let remaining = records.filter { accessibleIDs.contains($0.id) }
        if remaining.count != records.count {
            applyRecords(remaining)
        }
        selectedIdentifiers.formIntersection(accessibleIDs)
        let staleIDs = indexEntriesByID.keys.filter { !accessibleIDs.contains($0) }
        for identifier in staleIDs {
            if let entry = indexEntriesByID.removeValue(forKey: identifier) {
                modelContext?.delete(entry)
            }
        }
        setGroups(makeCachedGroups(from: records))
        saveCache()
    }

    private func removeAllCachedEntries() {
        guard let modelContext else { return }
        let entries = indexEntriesByID.isEmpty
            ? ((try? modelContext.fetch(FetchDescriptor<AssetIndexEntry>())) ?? [])
            : Array(indexEntriesByID.values)
        for entry in entries { modelContext.delete(entry) }
        indexEntriesByID.removeAll()
        setScanComplete(false)
        saveCache()
    }

    private func setScanComplete(_ complete: Bool) {
        isScanComplete = complete
        UserDefaults.standard.set(complete, forKey: Self.scanCompletionKey)
    }

    private func makeCachedGroups(from restored: [MediaRecord]) -> [DuplicateGroup] {
        let candidates = restored.compactMap { record -> FingerprintedAsset? in
            guard let fingerprint = record.fingerprint else { return nil }
            return FingerprintedAsset(id: record.id, fingerprint: fingerprint)
        }
        let recordByID = Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0) })
        let sensitivity = ScanSensitivity.current
        var groups = DuplicateGrouper.groups(
            from: candidates,
            hammingThreshold: sensitivity.hammingThreshold,
            colorThreshold: sensitivity.colorThreshold
        ).map { ids in
            let members = ids.compactMap { recordByID[$0] }
            let digestValues = Set(members.compactMap(\.digest))
            let kind: DuplicateKind = digestValues.count == 1 && members.allSatisfy { $0.digest != nil }
                ? .exact
                : .similar
            return DuplicateGroup(
                id: "cached-\(ids[0])",
                assetIDs: ids,
                kind: kind,
                recommendedKeeperID: recommendedKeeper(in: ids, recordByID: recordByID)
            )
        }
        let burstBuckets = Dictionary(grouping: restored.compactMap { record -> (String, String)? in
            guard let identifier = record.burstIdentifier else { return nil }
            return (identifier, record.id)
        }, by: \.0)
        for bucket in burstBuckets.values where bucket.count > 1 {
            let identifiers = bucket.map(\.1).sorted()
            groups.append(DuplicateGroup(
                id: "cached-burst-\(identifiers[0])",
                assetIDs: identifiers,
                kind: .burst,
                recommendedKeeperID: recommendedKeeper(in: identifiers, recordByID: recordByID)
            ))
        }
        return groups
    }

    private func loadCache() -> [String: AssetIndexEntry] {
        guard let modelContext,
              let entries = try? modelContext.fetch(FetchDescriptor<AssetIndexEntry>()) else {
            indexEntriesByID = [:]
            return [:]
        }
        indexEntriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.localIdentifier, $0) })
        return indexEntriesByID
    }

    private func persistBatch(_ recordsToPersist: [MediaRecord]) {
        guard let modelContext else { return }
        for record in recordsToPersist { persist(record) }
        saveCache()
    }

    private func persist(_ record: MediaRecord) {
        guard let modelContext else { return }
        let identifier = record.id
        let entry: AssetIndexEntry
        if let cached = indexEntriesByID[identifier] {
            entry = cached
        } else {
            entry = AssetIndexEntry(localIdentifier: identifier)
            modelContext.insert(entry)
            indexEntriesByID[identifier] = entry
        }
        if let fingerprint = record.fingerprint {
            entry.perceptualHash = Int64(bitPattern: fingerprint.differenceHash)
            entry.averageRed = Int(fingerprint.red)
            entry.averageGreen = Int(fingerprint.green)
            entry.averageBlue = Int(fingerprint.blue)
        }
        if let byteSize = record.byteSize { entry.byteSize = byteSize }
        if let digest = record.digest { entry.digest = digest }
        entry.updatedAt = .now
    }

    private func saveCache() {
        try? modelContext?.save()
    }
}

/// 图库整体统计，在记录更新时一次性计算，避免视图每帧全量过滤。
struct LibraryStats {
    var photoCount = 0
    var videoCount = 0
    var screenshotCount = 0
    var livePhotoCount = 0
    var knownBytes: Int64 = 0
    var unknownSizeCount = 0

    init() {}

    init(records: [MediaRecord]) {
        var photo = 0
        var video = 0
        var screenshot = 0
        var live = 0
        var bytes: Int64 = 0
        var unknown = 0
        for record in records {
            if record.kind == .video { video += 1 } else { photo += 1 }
            if record.isScreenshot { screenshot += 1 }
            if record.isLivePhoto { live += 1 }
            if let size = record.byteSize { bytes += size } else { unknown += 1 }
        }
        photoCount = photo
        videoCount = video
        screenshotCount = screenshot
        livePhotoCount = live
        knownBytes = bytes
        unknownSizeCount = unknown
    }
}

/// 待删清单摘要，O(1) 供底部条与确认弹窗读取。
struct SelectionSummary {
    var count = 0
    var bytes: Int64 = 0
    var unknownCount = 0
}
