import SwiftUI

/// Finds big files sitting in the user's own folders. Unlike the other two tabs
/// these are documents, not app junk, so nothing is ticked by default and
/// removal always goes through the confirmation sheet.
struct LargeFilesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isScanningLargeFiles {
                scanning
            } else if !model.didScanLargeFiles {
                intro
            } else if model.largeFiles.isEmpty {
                empty
            } else {
                fileList
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Large Files").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("The biggest files sitting in your folders")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.didScanLargeFiles && !model.largeFiles.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.size(model.largeFilesTotalSize))
                        .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(model.largeFilesTruncated
                         ? "largest \(model.largeFiles.count) files"
                         : "\(model.largeFiles.count) files")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $model.threshold) {
                ForEach(SizeThreshold.allCases) { Text("Over \($0.label)").tag($0) }
            }
            .labelsHidden().fixedSize()
            .disabled(model.isScanningLargeFiles)
            .onChange(of: model.threshold) { _ in
                if model.didScanLargeFiles { model.scanLargeFiles() }
            }
            Button { model.scanLargeFiles() } label: {
                Label(model.didScanLargeFiles ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .disabled(model.isScanningLargeFiles)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    // MARK: States

    private var scanning: some View {
        VStack { Spacer()
            ProgressView("Looking through your folders…").controlSize(.small)
            Spacer() }
    }

    private var intro: some View {
        centered(symbol: "externaldrive.fill", tint: Brand.accent,
                 title: "Find your biggest files",
                 subtitle: "Scans your home folder for files over the size you pick, skipping\nyour apps and their data. Nothing leaves without your say-so.") {
            Button { model.scanLargeFiles() } label: {
                Text("Scan for Large Files")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
    }

    private var empty: some View {
        centered(symbol: "checkmark.seal.fill", tint: .green,
                 title: "Nothing over \(model.threshold.label)",
                 subtitle: "No files that big in your folders. Try a smaller size.") { EmptyView() }
    }

    // MARK: List

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                let allOn = !model.largeFiles.isEmpty && model.largeFiles.allSatisfy(\.isSelected)
                let anyOn = model.largeFiles.contains(where: \.isSelected)
                Button { model.setAllLargeFiles(selected: !allOn) } label: {
                    HStack(spacing: 8) {
                        SelectCircle(isOn: allOn, mixed: anyOn && !allOn)
                        Text("Select All").font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Picker("", selection: $model.largeFileSort) {
                    ForEach(LargeFileSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize().controlSize(.small)
            }
            .padding(.horizontal, 22).padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.sortedLargeFiles) { LargeFileRow(file: $0) }
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
    }

    private var footer: some View {
        let files = model.selectedLargeFiles
        return HStack {
            Text(files.isEmpty
                 ? "Nothing selected"
                 : "\(files.count) selected • \(Format.size(model.selectedLargeFilesSize))")
                .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(files.isEmpty ? .secondary : .primary)
            Spacer()
            Button { model.requestLargeFileRemoval() } label: {
                Text("Move to Trash")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(files.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.3))
                                              : AnyShapeStyle(Brand.danger),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain).disabled(files.isEmpty)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func centered<Content: View>(symbol: String, tint: Color, title: String,
                                         subtitle: String,
                                         @ViewBuilder action: () -> Content) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(tint)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action().padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row

private struct LargeFileRow: View {
    @EnvironmentObject var model: AppModel
    let file: LargeFile
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Button { model.toggleLargeFile(file) } label: {
                SelectCircle(isOn: file.isSelected)
            }.buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().interpolation(.high)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(file.folder).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                SizePill(bytes: file.sizeBytes, prominent: file.isSelected)
                Text(Format.modified(file.modified))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }

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
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(file.isSelected ? Color.primary.opacity(0.07)
                      : (hovering ? Color.primary.opacity(0.035) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.toggleLargeFile(file) }
        .onHover { hovering = $0 }
    }
}
