import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 4) {
                SidebarItem(
                    title: "Uninstaller",
                    subtitle: model.apps.isEmpty ? "Scanning…" : "\(model.apps.count) apps",
                    symbol: "trash.fill",
                    isSelected: model.section == .uninstaller
                ) { model.section = .uninstaller }

                SidebarItem(
                    title: "Leftovers",
                    subtitle: model.didScanLeftovers
                        ? (model.leftovers.isEmpty ? "All clean" : "\(model.leftovers.count) found")
                        : "Tap to scan",
                    symbol: "sparkles",
                    isSelected: model.section == .leftovers
                ) { model.section = .leftovers }
            }
            .padding(.horizontal, 10)

            Spacer()

            reclaimableFooter
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            Text("Sweep")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var reclaimableFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.horizontal, 14)
            HStack(spacing: 10) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.size(model.totalReclaimable))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("in installed apps")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 4)
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Brand.gradient)
                                         : AnyShapeStyle(Color.secondary.opacity(0.14)))
                        .frame(width: 28, height: 28)
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.06)
                          : (hovering ? Color.primary.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
