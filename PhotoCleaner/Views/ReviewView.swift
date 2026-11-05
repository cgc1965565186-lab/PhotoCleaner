import SwiftUI

/// 重复整理页：按类别列出分组，组内并排比较，支持一键保留建议项。
struct ReviewListView: View {
    @Bindable var store: AppStore
    let kind: DuplicateKind

    private var groups: [DuplicateGroup] {
        store.groups(for: kind)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.records.isEmpty {
                        ContentUnavailableView(
                            "还没有扫描结果",
                            systemImage: kind.symbol,
                            description: Text("回到「整理」页开始智能扫描后，这里会显示\(kind.title)的分组。")
                        )
                        .padding(.top, 32)
                    } else if groups.isEmpty {
                        ContentUnavailableView(
                            "没有发现\(kind.title)",
                            systemImage: kind.symbol,
                            description: Text(kind.summary + "。图库更新后重新扫描即可。")
                        )
                        .padding(.top, 32)
                    } else {
                        summaryHeader
                        LazyVStack(spacing: 12) {
                            ForEach(groups) { group in
                                DuplicateGroupCard(store: store, group: group)
                            }
                        }
                        Text("建议仅供参考；删除项由你逐项确认。")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
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
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(groups.count) 组待处理")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
        }
    }
}

/// 重复组卡片：横排缩略图并排比较，标记建议保留项。
/// 成员通过记录索引 O(1) 查找，选中状态由卡片自身追踪，互不牵连整页重绘。
struct DuplicateGroupCard: View {
    @Bindable var store: AppStore
    let group: DuplicateGroup

    private var members: [MediaRecord] {
        group.assetIDs.compactMap { store.recordsByID[$0] }
    }

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("\(members.count) 项")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if group.kind == .exact {
                        Label("内容一致", systemImage: "equal")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.accentText)
                    }
                    Spacer()
                    if group.recommendedKeeperID != nil {
                        Button {
                            store.selectAllExceptRecommended(in: group)
                        } label: {
                            Label("仅保留建议项", systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.accentText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(minHeight: 32)
                                .background(Palette.accent.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("选中组内除建议保留项之外的全部成员")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(members) { record in
                            memberCard(record)
                        }
                    }
                }
            }
        }
    }

    private func memberCard(_ record: MediaRecord) -> some View {
        let isSelected = store.selectedIdentifiers.contains(record.id)
        let isKeeper = record.id == group.recommendedKeeperID

        return VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                NavigationLink(value: HomeRoute.detail(record.id)) {
                    AssetThumbnailView(
                        asset: record.asset,
                        size: CGSize(width: 112, height: 104),
                        networkAllowed: false
                    )
                    .frame(width: 112, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { store.toggleSelection(for: record) } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Palette.accent : .white, .black.opacity(0.25))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            if isKeeper {
                Text("建议保留")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.accentText)
            }
            Text(DisplayFormat.date(record.creationDate))
            Text("\(record.width) × \(record.height)")
            Text(DisplayFormat.bytes(record.byteSize))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Palette.secondaryText)
        .frame(width: 112, alignment: .leading)
        .padding(5)
        .background(
            isSelected ? Palette.accent.opacity(0.09) : .clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityLabel("\(group.kind.title)，\(DisplayFormat.date(record.creationDate))，\(record.width) 乘 \(record.height)，\(DisplayFormat.bytes(record.byteSize))\(isKeeper ? "，建议保留" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
