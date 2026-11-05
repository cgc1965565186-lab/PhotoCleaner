import Foundation
import Photos
import SwiftData

@Model
final class AssetIndexEntry {
    @Attribute(.unique) var localIdentifier: String
    var perceptualHash: Int64?
    var averageRed: Int
    var averageGreen: Int
    var averageBlue: Int
    var byteSize: Int64?
    var digest: String?
    var updatedAt: Date

    init(
        localIdentifier: String,
        perceptualHash: Int64? = nil,
        averageRed: Int = 0,
        averageGreen: Int = 0,
        averageBlue: Int = 0,
        byteSize: Int64? = nil,
        digest: String? = nil,
        updatedAt: Date = .now
    ) {
        self.localIdentifier = localIdentifier
        self.perceptualHash = perceptualHash
        self.averageRed = averageRed
        self.averageGreen = averageGreen
        self.averageBlue = averageBlue
        self.byteSize = byteSize
        self.digest = digest
        self.updatedAt = updatedAt
    }
}

enum MediaKind: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: "照片"
        case .video: "视频"
        }
    }
}

/// 图库浏览页的筛选范围；「整理」页的专项清单通过 push 携带初始范围进入。
enum LibraryCategory: String, CaseIterable, Identifiable {
    case all
    case similar
    case bursts
    case screenshots
    case livePhotos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .similar: "相似照片"
        case .bursts: "连拍"
        case .screenshots: "截图"
        case .livePhotos: "实况照片"
        case .videos: "视频"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .similar: "square.stack.3d.up"
        case .bursts: "camera.burst"
        case .screenshots: "rectangle.dashed"
        case .livePhotos: "livephoto"
        case .videos: "play.rectangle"
        }
    }

    /// 重复分组类别的成员来自相似组；普通浏览类别直接按媒体属性匹配。
    var isDuplicateCategory: Bool {
        self == .similar || self == .bursts
    }
}

enum MediaSort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case largest
    case smallest
    case longest
    case shortest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "拍摄时间 · 最新"
        case .oldest: "拍摄时间 · 最早"
        case .largest: "文件大小 · 最大"
        case .smallest: "文件大小 · 最小"
        case .longest: "视频时长 · 最长"
        case .shortest: "视频时长 · 最短"
        }
    }

    var requiresExactSize: Bool {
        self == .largest || self == .smallest
    }
}

struct LibraryFilters: Equatable {
    var category: LibraryCategory = .all
    var kind: MediaKind?
    var sort: MediaSort = .newest
    var dateFrom: Date?
    var dateTo: Date?
    var minimumMegabytes = ""
    var maximumMegabytes = ""
    var favoritesOnly = false

    var hasConditions: Bool {
        kind != nil || dateFrom != nil || dateTo != nil ||
        !minimumMegabytes.isEmpty || !maximumMegabytes.isEmpty || favoritesOnly
    }
}

struct MediaRecord: Identifiable, Hashable {
    let asset: PHAsset
    var byteSize: Int64?
    var fingerprint: ImageFingerprint?
    var digest: String?

    var id: String { asset.localIdentifier }
    var kind: MediaKind { asset.mediaType == .video ? .video : .photo }
    var creationDate: Date? { asset.creationDate }
    var width: Int { asset.pixelWidth }
    var height: Int { asset.pixelHeight }
    var duration: TimeInterval { asset.duration }
    var isFavorite: Bool { asset.isFavorite }
    var isScreenshot: Bool { asset.mediaSubtypes.contains(.photoScreenshot) }
    var isLivePhoto: Bool { asset.mediaSubtypes.contains(.photoLive) }
    var burstIdentifier: String? { asset.burstIdentifier }

    static func == (lhs: MediaRecord, rhs: MediaRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum DuplicateKind: String, CaseIterable, Identifiable {
    case exact
    case similar
    case burst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exact: "完全相同"
        case .similar: "视觉相似"
        case .burst: "同组连拍"
        }
    }

    var symbol: String {
        switch self {
        case .exact: "equal.square"
        case .similar: "square.stack.3d.up"
        case .burst: "camera.burst"
        }
    }

    var summary: String {
        switch self {
        case .exact: "内容一致的文件，可放心只保留一份"
        case .similar: "画面接近的照片，适合并排比较后取舍"
        case .burst: "同一次连拍产生的照片"
        }
    }
}

struct DuplicateGroup: Identifiable, Equatable {
    let id: String
    let assetIDs: [String]
    let kind: DuplicateKind
    let recommendedKeeperID: String?
}

struct StorageSnapshot {
    var totalBytes: Int64?
    var availableBytes: Int64?

    var usedBytes: Int64? {
        guard let totalBytes, let availableBytes else { return nil }
        return max(0, totalBytes - availableBytes)
    }
}

/// 图库查询：纯函数过滤与排序，浏览页与整理清单共用同一套语义。
enum MediaQuery {
    static func filter(
        records: [MediaRecord],
        duplicateGroups: [DuplicateGroup],
        filters: LibraryFilters
    ) -> [MediaRecord] {
        let groupIDs: Set<String> = {
            switch filters.category {
            case .similar:
                Set(duplicateGroups.filter { $0.kind != .burst }.flatMap(\.assetIDs))
            case .bursts:
                Set(duplicateGroups.filter { $0.kind == .burst }.flatMap(\.assetIDs))
            default:
                []
            }
        }()

        var result = records.filter { record in
            switch filters.category {
            case .all: true
            case .similar: groupIDs.contains(record.id)
            case .bursts: record.burstIdentifier != nil
            case .screenshots: record.isScreenshot
            case .livePhotos: record.isLivePhoto
            case .videos: record.kind == .video
            }
        }

        if let kind = filters.kind {
            result = result.filter { $0.kind == kind }
        }
        if filters.favoritesOnly {
            result = result.filter(\.isFavorite)
        }
        if let dateFrom = filters.dateFrom {
            result = result.filter { ($0.creationDate ?? .distantPast) >= dateFrom }
        }
        if let dateTo = filters.dateTo {
            let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: dateTo) ?? dateTo
            result = result.filter { ($0.creationDate ?? .distantFuture) < dayAfter }
        }

        let minimum = Double(filters.minimumMegabytes).map { Int64($0 * 1_048_576) }
        let maximum = Double(filters.maximumMegabytes).map { Int64($0 * 1_048_576) }
        if minimum != nil || maximum != nil {
            result = result.filter { record in
                guard let size = record.byteSize else { return false }
                if let minimum, size < minimum { return false }
                if let maximum, size > maximum { return false }
                return true
            }
        }

        sort(&result, by: filters.sort)
        return result
    }

    static func unknownSizeCount(records: [MediaRecord], filters: LibraryFilters) -> Int {
        var filtered = records
        switch filters.category {
        case .all: break
        case .similar, .bursts: break
        case .screenshots: filtered = filtered.filter(\.isScreenshot)
        case .livePhotos: filtered = filtered.filter(\.isLivePhoto)
        case .videos: filtered = filtered.filter { $0.kind == .video }
        }
        return filtered.filter { $0.byteSize == nil }.count
    }

    private static func sort(_ result: inout [MediaRecord], by sort: MediaSort) {
        switch sort {
        case .newest:
            result.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest:
            result.sort { ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture) }
        case .largest:
            result.sort { ($0.byteSize ?? -1) > ($1.byteSize ?? -1) }
        case .smallest:
            result.sort { ($0.byteSize ?? Int64.max) < ($1.byteSize ?? Int64.max) }
        case .longest:
            result.sort { $0.duration > $1.duration }
        case .shortest:
            result.sort { $0.duration < $1.duration }
        }
    }
}

/// 完全重复的判定依据：字节数、像素尺寸与感知哈希完全一致。
/// 字节数不同的两个文件必不相同，因此该判定无需读取媒体内容。
enum DigestFingerprint {
    static func make(byteSize: Int64?, width: Int, height: Int, differenceHash: UInt64?) -> String? {
        guard let byteSize else { return nil }
        let hashPart = differenceHash.map { String($0) } ?? "none"
        return "\(byteSize)|\(width)x\(height)|\(hashPart)"
    }
}

/// 相似判定灵敏度，映射感知哈希汉明距离与颜色距离阈值。
enum ScanSensitivity: String, CaseIterable, Identifiable {
    case strict
    case standard
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: "严格"
        case .standard: "标准"
        case .relaxed: "宽松"
        }
    }

    var detail: String {
        switch self {
        case .strict: "只显示画面非常接近的照片，误报最少"
        case .standard: "均衡的判定，适合大多数图库"
        case .relaxed: "连构图接近的也归为相似，候选更多"
        }
    }

    var hammingThreshold: Int {
        switch self {
        case .strict: 3
        case .standard: 5
        case .relaxed: 8
        }
    }

    var colorThreshold: Int {
        switch self {
        case .strict: 80
        case .standard: 120
        case .relaxed: 160
        }
    }

    static var current: ScanSensitivity {
        ScanSensitivity(rawValue: UserDefaults.standard.string(forKey: "scanSensitivity") ?? "") ?? .standard
    }
}

/// 蜂窝网络下的读取策略。
enum CellularPolicy: String, CaseIterable, Identifiable {
    case ask
    case wifiOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "每次询问"
        case .wifiOnly: "仅 Wi-Fi"
        }
    }

    static var current: CellularPolicy {
        CellularPolicy(rawValue: UserDefaults.standard.string(forKey: "cellularPolicy") ?? "") ?? .ask
    }
}
