import Photos
import SwiftUI
import UIKit

/// 缩略图共享缓存：PHCachingImageManager 预热 + NSCache 复用，
/// 请求分辨率始终按屏幕缩放倍率换算，避免按点数请求导致的模糊或超采样。
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 800
    }

    func image(for asset: PHAsset, pixelSize: CGSize, networkAllowed: Bool) async -> UIImage? {
        let key = "\(asset.localIdentifier)-\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = await request(asset: asset, pixelSize: pixelSize, networkAllowed: networkAllowed)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    func prefetch(_ assets: [PHAsset], pixelSize: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        manager.startCachingImages(
            for: assets,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    func stopPrefetching() {
        manager.stopCachingImagesForAllAssets()
    }

    private func request(asset: PHAsset, pixelSize: CGSize, networkAllowed: Bool) async -> UIImage? {
        let gate = RequestGate<UIImage?>(cancelledValue: nil)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                gate.install(continuation)
                guard !Task.isCancelled else {
                    gate.cancel()
                    return
                }

                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = networkAllowed
                let requestID = manager.requestImage(
                    for: asset,
                    targetSize: pixelSize,
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    gate.finish(image)
                }
                gate.installCancellation { [manager] in
                    manager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

struct AssetThumbnailView: View {
    let asset: PHAsset
    let size: CGSize
    let networkAllowed: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.accent.opacity(0.08))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: asset.mediaType == .video ? "play.rectangle.fill" : "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.accent.opacity(0.55))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: asset.localIdentifier) { load() }
        .accessibilityHidden(true)
    }

    private func load() {
        let scale = max(UIScreen.main.scale, 2)
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard image == nil || image?.size.width ?? 0 < pixelSize.width else { return }
        Task { @MainActor in
            image = await ThumbnailStore.shared.image(
                for: asset,
                pixelSize: pixelSize,
                networkAllowed: networkAllowed
            )
        }
    }
}
