import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                HomeView(store: store)
                    .navigationDestination(for: HomeRoute.self, destination: destination)
            }
            .tabItem { Label("整理", systemImage: "sparkles.rectangle.stack") }
            .tag(0)

            NavigationStack {
                LibraryBrowseView(store: store)
                    .navigationDestination(for: HomeRoute.self, destination: destination)
            }
            .tabItem { Label("图库", systemImage: "photo.on.rectangle.angled") }
            .tag(1)

            NavigationStack {
                SettingsView(store: store)
            }
            .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
            .tag(2)
        }
        .tint(Palette.accent)
        .task { await store.configure(with: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshLibraryAccess()
                store.refreshStorage()
            }
        }
        .alert("净屿", isPresented: alertIsPresented) {
            Button("知道了", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .confirmationDialog("扫描照片图库", isPresented: $store.showsScanConfirmation, titleVisibility: .visible) {
            Button("开始扫描") { store.startScan() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("扫描在本机完成，只读取缩略图与资源元数据，不上传照片。iCloud 项目读取缩略图可能消耗少量流量；扫描可随时取消。")
        }
        .confirmationDialog("蜂窝网络读取", isPresented: $store.showsCellularConfirmation, titleVisibility: .visible) {
            Button("继续使用蜂窝网络") { store.continueOnCellular() }
            Button("取消读取", role: .cancel) { store.cancelCellularOperation() }
        } message: {
            Text("当前使用蜂窝网络。读取 iCloud 项目的缩略图会消耗少量移动数据，原始照片和视频不会被下载。")
        }
        .confirmationDialog("确认删除所选项目", isPresented: $store.showsDeleteConfirmation, titleVisibility: .visible) {
            Button("继续删除", role: .destructive) { store.deleteSelected() }
            Button("再检查一下", role: .cancel) { }
        } message: {
            Text("已选择 \(store.selectedIdentifiers.count) 项 · 已测资源约 \(DisplayFormat.bytes(store.selectedEstimatedBytes))\(store.selectedUnknownSizeCount > 0 ? " · \(store.selectedUnknownSizeCount) 项大小未知" : "")。启用 iCloud 照片时，删除会同步到其他设备；项目会进入“最近删除”。")
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .review(let kind):
            ReviewListView(store: store, kind: kind)
        case .library(let category):
            LibraryBrowseView(store: store, initialCategory: category)
        case .detail(let identifier):
            AssetDetailView(store: store, identifier: identifier)
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )
    }
}
