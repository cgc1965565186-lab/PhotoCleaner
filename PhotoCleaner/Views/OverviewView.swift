import SwiftUI

/// 整理页：图库概况 + 智能扫描 + 专项整理清单。
/// 导航栈由 RootView 统一持有，二级页面通过 NavigationLink 值推入。
struct HomeView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                storageCard
                scanSection
                checklistSection
                if !store.statusMessage.isEmpty {
                    Text(store.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .refreshable { store.refreshStorage() }
        .sensoryFeedback(.selection, trigger: store.selectedTab)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("净屿")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .tracking(-0.8)
                Text("把空间留给重要的瞬间")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 48, height: 48)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    private var storageCard: some View {
        let total = store.storage.totalBytes
        let available = store.storage.availableBytes
        let used = store.storage.usedBytes
        let fraction = total.flatMap { total in used.map { Double($0) / Double(max(total, 1)) } } ?? 0

        return SurfaceCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    StorageRing(fraction: fraction)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("设备可用空间")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.secondaryText)
                        Text(DisplayFormat.bytes(available))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                        Text("总容量 \(DisplayFormat.bytes(total))")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    statBlock("照片", "\(store.libraryStats.photoCount)")
                    statBlock("视频", "\(store.libraryStats.videoCount)")
                    statBlock("图库大小", store.libraryStats.unknownSizeCount == 0 && !store.records.isEmpty
                        ? DisplayFormat.bytes(store.libraryStats.knownBytes)
                        : "待扫描")
                }
                Text("容量来自 iOS 设备空间信息；图库大小由照片库元数据汇总。")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanSection: some View {
        VStack(spacing: 12) {
            PrimaryActionButton(
                title: store.isScanning ? "正在扫描…" : "开始智能扫描",
                subtitle: store.isScanning ? store.statusMessage : "识别重复、相似与占空间的媒体"
            ) {
                if store.isScanning { store.cancelScan() } else { store.requestScan() }
            }

            if store.isScanning {
                progressCard
            }
        }
    }

    private var progressCard: some View {
        SurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("扫描进度").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(store.scanProgress * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Button("取消") { store.cancelScan() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }
                ProgressView(value: store.scanProgress)
                    .tint(Palette.accent)
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var checklistSection: some View {
        VStack(spacing: 12) {
            SectionHeading(title: "整理清单", subtitle: "逐项进入，比完再删")
            ChecklistRow(
                symbol: "equal.square.fill",
                title: "完全重复",
                detail: "内容一致的文件，只留一份",
                value: groupValue(store.groups(for: .exact).count, unit: "组"),
                tint: Palette.accent,
                route: .review(.exact)
            )
            ChecklistRow(
                symbol: "square.stack.3d.up.fill",
                title: "视觉相似",
                detail: "画面接近的照片，并排比较",
                value: groupValue(store.groups(for: .similar).count, unit: "组"),
                tint: Color(red: 0.56, green: 0.55, blue: 0.78),
                route: .review(.similar)
            )
            ChecklistRow(
                symbol: "camera.burst.fill",
                title: "同组连拍",
                detail: "一次连拍产生的多张照片",
                value: groupValue(store.groups(for: .burst).count, unit: "组"),
                tint: Color(red: 0.83, green: 0.54, blue: 0.32),
                route: .review(.burst)
            )
            ChecklistRow(
                symbol: "rectangle.dashed",
                title: "截图",
                detail: "集中翻看，通常清理价值最高",
                value: countValue(store.libraryStats.screenshotCount, unit: "张"),
                tint: Color(red: 0.45, green: 0.78, blue: 0.70),
                route: .library(.screenshots)
            )
            ChecklistRow(
                symbol: "livephoto",
                title: "实况照片",
                detail: "占用约两倍空间，按需保留",
                value: countValue(store.libraryStats.livePhotoCount, unit: "张"),
                tint: Color(red: 0.34, green: 0.65, blue: 0.57),
                route: .library(.livePhotos)
            )
            ChecklistRow(
                symbol: "play.rectangle.fill",
                title: "视频",
                detail: "单个体积最大，适合按大小排",
                value: countValue(store.libraryStats.videoCount, unit: "个"),
                tint: Color(red: 0.68, green: 0.50, blue: 0.78),
                route: .library(.videos)
            )
        }
    }

    private func groupValue(_ count: Int, unit: String) -> String {
        count > 0 ? "\(count) \(unit)" : "无"
    }

    private func countValue(_ count: Int, unit: String) -> String {
        count > 0 ? "\(count) \(unit)" : "无"
    }
}

enum HomeRoute: Hashable {
    case review(DuplicateKind)
    case library(LibraryCategory)
    case detail(String)
}
