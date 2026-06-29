import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let app = model.selectedApp {
                detail(for: app)
            } else {
                EmptyDetail()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Detail for a selected app

    private func detail(for app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            appHeader(app)
            Divider()

            if model.isScanningFiles {
                Spacer()
                ProgressView("Finding associated files…").controlSize(.small)
                Spacer()
            } else {
                fileList
            }

            footer(app)
        }
    }

    // MARK: Header

    private func appHeader(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: app.icon)
                .resizable().interpolation(.high)
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 21, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    if let v = app.version {
                        Text("Version \(v)").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    if let bid = app.bundleID {
                        Text(bid).font(.system(size: 11))
                            .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(Format.lastUsed(app.lastUsed))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.size(model.relatedFilesTotalSize))
                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                Text("\(model.relatedFiles.count) item\(model.relatedFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    // MARK: Grouped file list

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                // "Select All" checkbox: checked when every removable item is on,
                // a dash when only some are, empty when none. Clicking toggles all.
                let toggleable = model.relatedFiles.filter { $0.category != .binary }
                let allOn = !toggleable.isEmpty && toggleable.allSatisfy(\.isSelected)
                let anyOn = toggleable.contains(where: \.isSelected)
                HStack(spacing: 9) {
                    Button { model.setAllFiles(selected: !allOn) } label: {
                        HStack(spacing: 8) {
                            SelectCircle(isOn: allOn, mixed: anyOn && !allOn)
                            Text("Select All")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(toggleable.isEmpty)
                    Spacer()
                    Text("\(model.selectedFilesCount) of \(model.relatedFiles.count) selected")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)

                ForEach(groupedCategories, id: \.self) { category in
                    CategorySection(category: category,
                                    files: model.relatedFiles.filter { $0.category == category })
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var groupedCategories: [FileCategory] {
        Array(Set(model.relatedFiles.map(\.category))).sorted { $0.order < $1.order }
    }

    // MARK: Footer (Uninstall)

    private func footer(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Removes \(Format.size(model.selectedFilesSize))")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text("Items are moved to the Trash")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.requestUninstall() } label: {
                Text("Uninstall")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(model.selectedFilesCount > 0 ? AnyShapeStyle(Brand.danger)
                                                             : AnyShapeStyle(Color.secondary.opacity(0.3)),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(model.selectedFilesCount == 0)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Category section

private struct CategorySection: View {
    @EnvironmentObject var model: AppModel
    let category: FileCategory
    let files: [RelatedFile]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.toggleCategory(category) } label: {
                HStack(spacing: 9) {
                    CategoryGlyph(category: category, size: 26)
                    Text(category.rawValue).font(.system(size: 12.5, weight: .semibold))
                    Text("\(files.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                    Spacer()
                    SizePill(bytes: files.reduce(0) { $0 + $1.sizeBytes })
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(category == .binary)
            .padding(.horizontal, 22)

            VStack(spacing: 0) {
                ForEach(files) { file in
                    FileRow(file: file)
                    if file.id != files.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 18)
        }
    }
}

// MARK: - File row

private struct FileRow: View {
    @EnvironmentObject var model: AppModel
    let file: RelatedFile
    @State private var hovering = false

    private var locked: Bool { file.category == .binary }

    var body: some View {
        HStack(spacing: 10) {
            Button { model.toggleFile(file) } label: {
                SelectCircle(isOn: file.isSelected, locked: locked)
            }
            .buttonStyle(.plain)
            .disabled(locked)

            Text(file.displayPath)
                .font(.system(size: 11.5))
                .foregroundStyle(file.isSelected ? .primary : .secondary)
                .lineLimit(1).truncationMode(.middle)
                .help(file.url.path)

            Spacer(minLength: 8)

            Text(Format.size(file.sizeBytes))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { if !locked { model.toggleFile(file) } }
        .onHover { hovering = $0 }
    }
}

// MARK: - Empty state

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select an app to uninstall")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Sweep finds caches, preferences, containers and other\nleftover files so nothing gets left behind.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
