import SwiftUI
import UIKit

enum Palette {
    static let accent = Color(red: 0.13, green: 0.57, blue: 0.68)
    static let accentDeep = Color(red: 0.06, green: 0.37, blue: 0.48)
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.80, blue: 0.83, alpha: 1)
            : UIColor(red: 0.05, green: 0.32, blue: 0.43, alpha: 1)
    })
    static let mint = Color(red: 0.45, green: 0.78, blue: 0.70)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let secondaryText = Color(uiColor: .secondaryLabel)
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
            }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
}

struct StorageRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.accent.opacity(0.12), lineWidth: 11)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [Palette.mint, Palette.accent, Palette.accentDeep],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "sparkle")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Palette.accent)
        }
        .frame(width: 76, height: 76)
        .accessibilityLabel("已使用空间比例 \(Int(fraction * 100))%")
    }
}

struct PrimaryActionButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Palette.accent, Palette.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(.white.opacity(0.10))
                            .frame(width: 120, height: 120)
                            .blur(radius: 1)
                            .offset(x: 30, y: -58)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(subtitle)
    }
}

enum DisplayFormat {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "待计算" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "日期未知" }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ value: Date?) -> String {
        guard let value else { return "日期未知" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

/// 整理清单行：图标 + 标题 + 说明 + 计数，标准 NavigationLink 推入对应结果页。
struct ChecklistRow: View {
    let symbol: String
    let title: String
    let detail: String
    let value: String
    let tint: Color
    let route: HomeRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.accentText)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText.opacity(0.55))
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 详情页信息行。
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
    }
}

/// 底部待删清单条：显示已选数量与估算大小，确认后提交删除。
struct SelectionBar: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("已选 \(store.selectedIdentifiers.count) 项")
                    .font(.subheadline.weight(.semibold))
                Text("已测约 \(DisplayFormat.bytes(store.selectedEstimatedBytes))\(store.selectedUnknownSizeCount > 0 ? " · \(store.selectedUnknownSizeCount) 项未知" : "")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Button("清空") { store.clearSelection() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(minHeight: 44)
            Button {
                store.requestDelete()
            } label: {
                Label("审核删除", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                    .foregroundStyle(Palette.accentDeep)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(LinearGradient(colors: [Palette.accent, Palette.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
                .opacity(0.82)
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
        .foregroundStyle(.white)
        .shadow(color: Palette.accentDeep.opacity(0.22), radius: 18, y: 8)
    }
}
