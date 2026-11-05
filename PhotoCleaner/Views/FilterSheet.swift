import SwiftUI

/// 排序与筛选面板。大小数据来自照片库元数据，全部条目始终可筛。
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: LibraryFilters

    @State private var kindSelection: String

    init(filters: Binding<LibraryFilters>) {
        _filters = filters
        _kindSelection = State(initialValue: filters.wrappedValue.kind?.rawValue ?? "all")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("排序方式") {
                    Picker("排序", selection: $filters.sort) {
                        ForEach(MediaSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("媒体条件") {
                    Picker("类型", selection: $kindSelection) {
                        Text("全部媒体").tag("all")
                        ForEach(MediaKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    Toggle("仅显示收藏", isOn: $filters.favoritesOnly)
                }

                Section("拍摄日期") {
                    Toggle("起始日期", isOn: Binding(
                        get: { filters.dateFrom != nil },
                        set: {
                            let start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
                            filters.dateFrom = $0 ? (filters.dateFrom ?? Calendar.current.startOfDay(for: start)) : nil
                        }
                    ))
                    if filters.dateFrom != nil {
                        DatePicker("从", selection: optionalDate($filters.dateFrom), displayedComponents: .date)
                    }
                    Toggle("结束日期", isOn: Binding(
                        get: { filters.dateTo != nil },
                        set: { filters.dateTo = $0 ? (filters.dateTo ?? Calendar.current.startOfDay(for: .now)) : nil }
                    ))
                    if filters.dateTo != nil {
                        DatePicker("至", selection: optionalDate($filters.dateTo), displayedComponents: .date)
                    }
                }

                Section {
                    HStack {
                        Text("最小")
                        TextField("MB", text: $filters.minimumMegabytes)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("MB").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("最大")
                        TextField("MB", text: $filters.maximumMegabytes)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("MB").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("文件大小")
                } footer: {
                    Text("文件大小来自照片库元数据，所有条目都可以直接筛选。")
                }

                Section {
                    Button("清除筛选条件", role: .destructive) {
                        filters = LibraryFilters()
                        kindSelection = "all"
                    }
                }
            }
            .navigationTitle("排序与筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: kindSelection) { _, value in
                filters.kind = MediaKind(rawValue: value)
            }
        }
    }

    private func optionalDate(_ value: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: { value.wrappedValue ?? .now },
            set: { value.wrappedValue = $0 }
        )
    }
}
