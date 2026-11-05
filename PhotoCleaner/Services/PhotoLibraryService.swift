import AVFoundation
import AVKit
import CryptoKit
import Foundation
import Photos
import UIKit

/// 单个资产的资源摘要。文件大小来自照片库元数据，不读取媒体内容。
struct ResourceSummary {
    let byteSize: Int64?
    let resourceCount: Int
    let locallyAvailable: Bool
}

/// 照片图库访问层。所有方法线程安全，可在任意执行器调用。
final class PhotoLibraryService: @unchecked Sendable {
    private let imageManager = PHCachingImageManager()

    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func assetCount() -> Int {
        PHAsset.fetchAssets(with: PHFetchOptions()).count
    }

    func fetchAssets(identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func stopCachingThumbnails() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// 预热缩略图缓存，供网格滚动前调用。
    func startCachingThumbnails(for assets: [PHAsset], targetSize: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    func thumbnail(for asset: PHAsset, targetSize: CGSize, networkAllowed: Bool) async -> UIImage? {
        let gate = RequestGate<UIImage?>(cancelledValue: nil)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                gate.install(continuation)
                guard !Task.isCancelled else {
                    gate.cancel()
                    return
                }

                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = networkAllowed
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    gate.finish(image)
                }
                gate.installCancellation { [imageManager] in
                    imageManager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            gate.cancel()
        }
    }

    /// 视频播放资源，iCloud 视频按需流式读取。
    func playerItem(for asset: PHAsset, networkAllowed: Bool) async -> AVPlayerItem? {
        let gate = RequestGate<AVPlayerItem?>(cancelledValue: nil)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
                gate.install(continuation)

                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = networkAllowed
                options.deliveryMode = .automatic
                options.version = .current
                PHImageManager.default().requestPlayerItem(
                    forVideo: asset,
                    options: options
                ) { item, _ in
                    gate.finish(item)
                }
            }
        } onCancel: {
            gate.cancel()
        }
    }

    /// 读取资源元数据（字节数、本机可用性），不触发任何媒体数据读取或 iCloud 下载。
    func resourceSummary(for asset: PHAsset) -> ResourceSummary {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else {
            return ResourceSummary(byteSize: nil, resourceCount: 0, locallyAvailable: true)
        }

        var total: Int64 = 0
        var measured = false
        var locallyAvailable = true
        for resource in resources where Self.isPrimaryResource(resource) {
            if let size = Self.fileSize(of: resource) {
                total += size
                measured = true
            }
            if !Self.isLocallyAvailable(resource) { locallyAvailable = false }
        }
        return ResourceSummary(
            byteSize: measured ? total : nil,
            resourceCount: resources.count,
            locallyAvailable: locallyAvailable
        )
    }

    func deleteAssets(identifiers: [String]) async throws {
        let assets = fetchAssets(identifiers: identifiers)
        guard !assets.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibraryError.deleteFailed)
                }
            })
        }
    }

    // MARK: - 资源元数据

    /// 计入文件大小的主资源类型；缩略图、调整数据等派生资源排除。
    private static func isPrimaryResource(_ resource: PHAssetResource) -> Bool {
        switch resource.type {
        case .photo, .video, .pairedVideo, .fullSizePhoto, .fullSizeVideo:
            true
        default:
            false
        }
    }

    /// 文件大小存在于资源元数据中，通过键值读取，零 IO。
    static func fileSize(of resource: PHAssetResource) -> Int64? {
        guard let value = try? resource.value(forKey: "fileSize") else { return nil }
        if let size = value as? Int64 { return size }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }

    static func isLocallyAvailable(_ resource: PHAssetResource) -> Bool {
        (try? resource.value(forKey: "locallyAvailable")) as? Bool ?? true
    }
}

enum PhotoLibraryError: LocalizedError {
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .deleteFailed: "照片库没有完成删除，请检查权限或重新选择项目。"
        }
    }
}

final class RequestGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelledValue: Value
    private var result: Value
    private var hasResult = false
    private var wasCancelled = false
    private var continuation: CheckedContinuation<Value, Never>?
    private var cancelAction: (() -> Void)?

    init(cancelledValue: Value) {
        self.cancelledValue = cancelledValue
        self.result = cancelledValue
    }

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        let completed = hasResult
        let completedResult = result
        if !hasResult { self.continuation = continuation }
        lock.unlock()
        if completed {
            continuation.resume(returning: completedResult)
        }
    }

    func installCancellation(_ action: @escaping () -> Void) {
        lock.lock()
        let shouldCancel = wasCancelled
        if !hasResult && !wasCancelled { cancelAction = action }
        lock.unlock()
        if shouldCancel { action() }
    }

    func finish(_ value: Value) {
        lock.lock()
        guard !hasResult else {
            lock.unlock()
            return
        }
        hasResult = true
        result = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func cancel() {
        lock.lock()
        guard !hasResult else {
            lock.unlock()
            return
        }
        wasCancelled = true
        hasResult = true
        result = cancelledValue
        let continuation = self.continuation
        let action = cancelAction
        self.continuation = nil
        cancelAction = nil
        lock.unlock()
        action?()
        continuation?.resume(returning: cancelledValue)
    }
}
