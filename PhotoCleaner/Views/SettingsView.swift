import Photos
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: AppStore

    @AppStorage("scanSensitivity") private var sensitivityRaw = ScanSensitivity.standard.rawValue
    @AppStorage("cellularPolicy") private var cellularPolicyRaw = CellularPolicy.ask.rawValue
    @State private var showsExporter = false

    private var sensitivity: ScanSensitivity {
        ScanSensitivity(rawValue: sensitivityRaw) ?? .standard
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                scanCard
                dataCard
                permissionCard
                privacyCard
                aboutCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .fileExporter(
            isPresented: $showsExporter,
            document: CSVExportDocument(text: store.duplicateExportText()),
            contentType: .commaSeparatedText,
            defaultFilename: "净屿整理结果"
        ) { result in
            if case .success(let url) = result {
                store.alertMessage = "整理结果已导出：\(url.lastPathComponent)"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("调整识别策略，管理数据与导出")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - 扫描与识别

    private var scanCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("扫描与识别", systemImage: "slider.horizontal.below.rectangle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("相似判定灵敏度")
                        .font(.subheadline.weight(.medium))
                    Picker("相似判定灵敏度", selection: $sensitivityRaw) {
                        ForEach(ScanSensitivity.allCases) { level in
                            Text(level.title).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: sensitivityRaw) { _, _ in
                        store.rebuildGroupsFromCache()
                    }
                    Text(sensitivity.detail + "。修改后立即按已有扫描结果重新分组，无需重新扫描。")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("蜂窝网络下读取 iCloud 缩略图")
                        .font(.subheadline.weight(.medium))
                    Picker("蜂窝网络策略", selection: $cellularPolicyRaw) {
                        ForEach(CellularPolicy.allCases) { policy in
                            Text(policy.title).tag(policy.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("「每次询问」在扫描前弹窗确认；「仅 Wi-Fi」遇到蜂窝网络会跳过本次读取。原始照片和视频在任何设置下都不会被下载。")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 数据与导出

    private var dataCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("数据与导出", systemImage: "externaldrive")
                    .font(.headline)

                HStack {
                    Text("本地扫描索引")
                        .font(.subheadline)
                    Spacer()
                    Text("\(store.indexEntryCount) 条")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }

                Button {
                    showsExporter = true
                } label: {
                    Label("导出整理结果（CSV）", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }
                .disabled(store.duplicateGroups.isEmpty)

                if store.duplicateGroups.isEmpty {
                    Text("扫描完成且发现重复后，可以把全部分组导出为表格，方便在电脑上对照清理。")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                Button(role: .destructive) {
                    store.clearLocalCache()
                } label: {
                    Label("清除本地索引", systemImage: "trash.slash")
                        .font(.subheadline.weight(.semibold))
                }
                Text("索引只保存照片标识、感知指纹和已测大小；清除后重新扫描即可重建，照片和视频不会被修改。")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 权限

    private var permissionCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("照片图库权限", systemImage: "photo.badge.key")
                    .font(.headline)
                HStack(spacing: 10) {
                    Circle()
                        .fill(store.hasPhotoAccess ? Palette.mint : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(accessDescription)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                }
                Button {
                    store.openSettings()
                } label: {
                    Label("打开系统设置", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }
            }
        }
    }

    // MARK: - 隐私与关于

    private var privacyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 11) {
                Label("隐私", systemImage: "hand.raised")
                    .font(.headline)
                SettingsLine(symbol: "iphone", title: "识别在本机完成", detail: "不上传照片，不使用账号或分析服务。")
                SettingsLine(symbol: "checkmark.shield", title: "删除前由你审核", detail: "选择项目并确认后才会提交给照片图库。")
            }
        }
    }

    private var aboutCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("关于", systemImage: "info.circle")
                    .font(.headline)
                HStack {
                    Text("版本")
                    Spacer()
                    Text("\(appVersion) · iOS 18+")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.accentText)
                Text("iOS 允许应用管理获得授权的照片图库；系统缓存和其他应用的数据不在可访问范围内。")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "v\(version)"
    }

    private var accessDescription: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: "已获得完整访问"
        case .limited: "有限访问 · 结果仅包含已授权项目"
        case .denied: "尚未授权"
        case .restricted: "此设备限制访问"
        case .notDetermined: "尚未请求权限"
        @unknown default: "权限状态未知"
        }
    }
}

private struct SettingsLine: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.accentText)
                .frame(width: 23)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// CSV 导出文档，供 fileExporter 写入用户选择的位置。
struct CSVExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    static let writableContentTypes: [UTType] = [.commaSeparatedText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
