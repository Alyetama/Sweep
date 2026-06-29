import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 300, idealWidth: 340)
            AppDetailView()
                .frame(minWidth: 380)
        }
    }

    // MARK: App list (master)

    private var appList: some View {
        VStack(spacing: 0) {
            listHeader

            if model.isLoadingApps && model.apps.isEmpty {
                Spacer()
                ProgressView("Scanning applications…")
                    .controlSize(.small)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.filteredApps) { app in
                            AppRow(app: app, isSelected: app.id == model.selectedAppID)
                                .onTapGesture { model.select(app) }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var listHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Applications")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Menu {
                    Picker("Sort by", selection: $model.sort) {
                        ForEach(AppSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Sort: \(model.sort.rawValue)", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search apps", text: $model.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

// MARK: - App row

struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: app.icon)
                .resizable().interpolation(.high)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(Format.lastUsed(app.lastUsed))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if app.sizeBytes < 0 {
                ProgressView().controlSize(.mini)
            } else {
                SizePill(bytes: app.sizeBytes, prominent: isSelected)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.08)
                      : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? Brand.accent.opacity(0.5) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
