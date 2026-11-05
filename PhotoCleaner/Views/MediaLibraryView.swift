import Photos
import SwiftUI

/// 图库浏览页：全量媒体浏览、筛选、选择删除。
/// 过滤与排序在后台执行并缓存结果，单元格为独立视图，选中变化只重绘受影响的格子。
struct LibraryBrowseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var store: AppStore
    @State private var filters: LibraryFilters
    @State private var showsFilters = false
    @State private var usesGrid = true
    @State private var displayedRecords: [MediaRecord] = []
    @State private var isRecomputing = false
    @State private var recomputeTask: Task<Void, Never>?

    init(store: AppStore, initialCategory: LibraryCategory = .all) {
        self.store = store
        var initial = LibraryFilters()
        initial.category = initialCategory
        _filters = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, store.selectionSummary.count == 0 ? 30 : 116)
            }
            .background(Palette.canvas.ignoresSafeArea())

            if store.selectionSummary.count > 0 {
                SelectionBar(store: store)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(filters.category == .all ? "图库" : filters.category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    usesGrid.toggle()
                } label: {
                    Image(systemName: usesGrid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(usesGrid ? "切换为列表" : "切换为网格")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsFilters = true } label: {
                    Image(systemName: filters.hasConditions || filters.sort != .newest
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("排序与筛选")
            }
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(filters: $filters)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.selectionSummary.count)
        .sensoryFeedback(.selection, trigger: store.selectionSummary.count)
        .task { recompute() }
        .onChange(of: filters) { _, _ in recompute() }
        .onChange(of: store.records) { _, _ in recompute() }
        .onChange(of: store.duplicateGroups) { _, _ in recompute() }
        .onDisappear { recomputeTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if store.records.isEmpty {
            emptyState
        } else if displayedRecords.isEmpty && isRecomputing {
            resultsHeader(recordCount: 0)
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 32)
        } else if displayedRecords.isEmpty {
            resultsHeader(recordCount: 0)
            noResults
        } else {
            resultsHeader(recordCount: displayedRecords.count)
            if usesGrid {
                LazyVGrid(columns: gridColumns, spacing: 13) {
                    ForEach(displayedRecords) { record in
                        LibraryGridCell(record: record, store: store)
                    }
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(displayedRecords) { record in
                        LibraryListCell(record: record, store: store)
                    }
                }
            }
        }
    }

    /// 后台重算当前筛选结果；数据未变时避免重复排序。
    private func recompute() {
        let records = store.records
        let groups = store.duplicateGroups
        let currentFilters = filters
        recomputeTask?.cancel()

        guard !records.isEmpty else {
            displayedRecords = []
            isRecomputing = false
            return
        }
        isRecomputing = true
        recomputeTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                MediaQuery.filter(records: records, duplicateGroups: groups, filters: currentFilters)
            }.value
            guard !Task.isCancelled else { return }
            displayedRecords = result
            isRecomputing = false
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    // MARK: - 区块

    private func resultsHeader(recordCount: Int) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(recordCount) 项")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(filters.hasConditions || filters.sort != .newest
                     ? "已应用筛选 · 轻点缩略图查看详情"
                     : "轻点查看详情 · 点右上角圆圈加入待删清单")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            if filters.hasConditions {
                Button("清除筛选") {
                    filters = LibraryFilters()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accentText)
            }
        }
    }

    private var noResults: some View {
        ContentUnavailableView(
            "没有符合条件的媒体",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("清除部分筛选条件，或扫描其他分类。")
        )
        .padding(.top, 24)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            store.isScanComplete && store.hasPhotoAccess ? "照片图库为空" : "还没有扫描结果",
            systemImage: "photo.on.rectangle.angled",
            description: Text(store.isScanComplete && store.hasPhotoAccess
                ? "添加照片后，可以随时扫描并整理图库。"
                : "回到「整理」页开始智能扫描，建立本地索引。")
        )
        .padding(.top, 32)
    }
}

// MARK: - 单元格
// 图片主体轻点进入详情；右上角勾选按钮常驻，随时可加入待删清单。

private struct LibraryGridCell: View {
    let record: MediaRecord
    @Bindable var store: AppStore

    var body: some View {
        let isSelected = store.selectedIdentifiers.contains(record.id)
        return ZStack(alignment: .topTrailing) {
            NavigationLink(value: HomeRoute.detail(record.id)) {
                MediaGridCell(record: record, isSelected: isSelected)
            }
            .buttonStyle(.plain)

            Button { store.toggleSelection(for: record) } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? Palette.accent : .white, .black.opacity(0.28))
                    .padding(7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "取消选择" : "选择")
        }
    }
}

private struct LibraryListCell: View {
    let record: MediaRecord
    @Bindable var store: AppStore

    var body: some View {
        let isSelected = store.selectedIdentifiers.contains(record.id)
        return HStack(spacing: 8) {
            NavigationLink(value: HomeRoute.detail(record.id)) {
                MediaListRow(record: record, isSelected: isSelected, showsSelectionMark: false)
            }
            .buttonStyle(.plain)

            Button { store.toggleSelection(for: record) } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.secondaryText.opacity(0.6))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "取消选择" : "选择")
        }
    }
}

// MARK: - 网格与列表单元外观

struct MediaGridCell: View {
    let record: MediaRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                AssetThumbnailView(
                    asset: record.asset,
                    size: CGSize(width: 112, height: 122),
                    networkAllowed: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: 122)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if record.kind == .video {
                        Label(DisplayFormat.duration(record.duration), systemImage: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.58), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(7)
                    }
                }
            }
            Text(DisplayFormat.date(record.creationDate))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
            Text(DisplayFormat.bytes(record.byteSize))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
        }
        .padding(6)
        .background(isSelected ? Palette.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityLabel("\(record.kind.title) · \(DisplayFormat.date(record.creationDate)) · \(DisplayFormat.bytes(record.byteSize))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MediaListRow: View {
    let record: MediaRecord
    let isSelected: Bool
    var showsSelectionMark = true

    var body: some View {
        HStack(spacing: 12) {
            AssetThumbnailView(
                asset: record.asset,
                size: CGSize(width: 72, height: 72),
                networkAllowed: false
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(record.kind.title).font(.subheadline.weight(.semibold))
                    if record.isFavorite { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink) }
                    if record.isLivePhoto {
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                    }
                }
                Text(DisplayFormat.date(record.creationDate))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                Text("\(record.width) × \(record.height) · \(DisplayFormat.bytes(record.byteSize))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsSelectionMark {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.secondaryText.opacity(0.6))
            }
        }
        .padding(10)
        .background(isSelected ? Palette.accent.opacity(0.07) : Palette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .contentShape(Rectangle())
    }
}
