import AVKit
import Photos
import SwiftUI

/// 媒体详情页：大图预览（可进全屏缩放）、视频内嵌播放、完整元信息与操作入口。
struct AssetDetailView: View {
    @Bindable var store: AppStore
    let identifier: String

    @State private var largeImage: UIImage?
    @State private var isLoadingImage = false
    @State private var showsFullscreenPreview = false
    @State private var player: AVPlayer?
    @State private var isLoadingPlayer = false

    private var record: MediaRecord? {
        store.record(with: identifier)
    }

    var body: some View {
        Group {
            if let record {
                content(for: record)
            } else {
                ContentUnavailableView(
                    "项目已不在图库中",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("这张照片或视频可能已被删除。")
                )
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.pause()
        }
    }

    private func content(for record: MediaRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                previewCard(for: record)
                infoCard(for: record)
                actionCard(for: record)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private func previewCard(for record: MediaRecord) -> some View {
        if record.kind == .video {
            videoPreview(for: record)
        } else {
            photoPreview(for: record)
        }
    }

    private func photoPreview(for record: MediaRecord) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.accent.opacity(0.08))
            if let largeImage {
                Image(uiImage: largeImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if isLoadingImage {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.accent.opacity(0.5))
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if largeImage != nil { showsFullscreenPreview = true }
        }
        .overlay(alignment: .bottomTrailing) {
            if largeImage != nil {
                Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
        .task(id: record.id) { await loadLargeImage(record) }
        .fullScreenCover(isPresented: $showsFullscreenPreview) {
            PhotoZoomPreview(image: largeImage)
        }
    }

    private func videoPreview(for record: MediaRecord) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black)
            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if isLoadingPlayer {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .task(id: record.id) { await loadPlayer(record) }
    }

    private func infoCard(for record: MediaRecord) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                InfoRow(label: "类型", value: record.kind.title + attributes(record))
                InfoRow(label: "拍摄时间", value: DisplayFormat.dateTime(record.creationDate))
                InfoRow(label: "分辨率", value: "\(record.width) × \(record.height)")
                if record.kind == .video {
                    InfoRow(label: "时长", value: DisplayFormat.duration(record.duration))
                }
                InfoRow(label: "文件大小", value: DisplayFormat.bytes(record.byteSize))
                InfoRow(label: "收藏", value: record.isFavorite ? "已收藏" : "未收藏")
            }
        }
    }

    private func actionCard(for record: MediaRecord) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("整理操作", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)

                Button {
                    store.toggleSelection(for: record)
                } label: {
                    Label(
                        store.selectedIdentifiers.contains(record.id) ? "移出待删清单" : "加入待删清单",
                        systemImage: store.selectedIdentifiers.contains(record.id) ? "minus.circle" : "trash"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        store.selectedIdentifiers.contains(record.id) ? Palette.accent.opacity(0.12) : Palette.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .foregroundStyle(Palette.accentText)
                }
                .buttonStyle(.plain)

                Text("加入清单后，可以在任意页面的底部待删条里统一审核删除。")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func attributes(_ record: MediaRecord) -> String {
        var parts: [String] = []
        if record.isScreenshot { parts.append(" · 截图") }
        if record.isLivePhoto { parts.append(" · 实况") }
        if record.burstIdentifier != nil { parts.append(" · 连拍") }
        return parts.joined()
    }

    private func loadLargeImage(_ record: MediaRecord) async {
        guard largeImage == nil else { return }
        isLoadingImage = true
        defer { isLoadingImage = false }
        largeImage = await store.detailImage(for: record.asset)
    }

    private func loadPlayer(_ record: MediaRecord) async {
        guard player == nil else { return }
        isLoadingPlayer = true
        defer { isLoadingPlayer = false }
        if let item = await store.playerItem(for: record.asset) {
            player = AVPlayer(playerItem: item)
        }
    }
}

/// 全屏照片预览：双击切换放大、捏合缩放、拖动平移。
struct PhotoZoomPreview: View {
    let image: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnifyGesture.simultaneously(with: panGesture))
                    .onTapGesture(count: 2) { toggleZoom() }
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("完成")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 10)
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clampScale(lastScale * value.magnification)
            }
            .onEnded { _ in
                lastScale = scale
                settle()
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.02 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
                settle()
            }
    }

    private func toggleZoom() {
        if scale > 1.02 {
            resetTransform()
        } else {
            scale = 2.5
            lastScale = 2.5
        }
    }

    private func settle() {
        if scale <= 1.02 {
            resetTransform()
        }
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 8)
    }
}
