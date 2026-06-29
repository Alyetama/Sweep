import SwiftUI

struct LeftoversView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isScanningLeftovers {
                scanning
            } else if !model.didScanLeftovers {
                intro
            } else if model.leftovers.isEmpty {
                allClean
            } else {
                groupList
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
                Text("Leftovers").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Orphaned files from apps you've already removed")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.didScanLeftovers && !model.leftovers.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.size(model.leftoversTotalSize))
                        .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("recoverable").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Button { model.scanLeftovers() } label: {
                Label(model.didScanLeftovers ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .disabled(model.isScanningLeftovers)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    // MARK: States

    private var scanning: some View {
        VStack { Spacer()
            ProgressView("Scanning ~/Library and /Library…").controlSize(.small)
            Spacer() }
    }

    private var intro: some View {
        centered(symbol: "sparkles", tint: Brand.accent,
                 title: "Find leftover files",
                 subtitle: "Scan your Library folders for caches, preferences and\nsupport files belonging to apps that are no longer installed.") {
            Button { model.scanLeftovers() } label: {
                Text("Scan for Leftovers")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
    }

    private var allClean: some View {
        centered(symbol: "checkmark.seal.fill", tint: .green,
                 title: "No leftovers found",
                 subtitle: "Every support file on this Mac belongs to an installed app.") { EmptyView() }
    }

    // MARK: Group list

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.leftovers) { group in
                    LeftoverGroupView(group: group)
                }
            }
            .padding(18)
        }
    }

    private var footer: some View {
        let count = model.leftovers.flatMap { $0.files.filter(\.isSelected) }.count
        let bytes = model.leftovers.reduce(0) { $0 + $1.selectedSize }
        return HStack {
            Text("\(count) item\(count == 1 ? "" : "s") selected • \(Format.size(bytes))")
                .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
            Spacer()
            Button { model.removeSelectedLeftovers() } label: {
                Text("Remove Selected")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(count > 0 ? AnyShapeStyle(Brand.danger)
                                          : AnyShapeStyle(Color.secondary.opacity(0.3)),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain).disabled(count == 0)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: Shared empty/intro layout

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

// MARK: - One leftover group (expandable card)

private struct LeftoverGroupView: View {
    @EnvironmentObject var model: AppModel
    let group: LeftoverGroup
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button { model.toggleLeftoverGroup(group) } label: {
                    SelectCircle(isOn: group.isFullySelected)
                }.buttonStyle(.plain)

                CategoryGlyph(category: group.files.first?.category ?? .other, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName).font(.system(size: 13.5, weight: .semibold))
                    Text(group.bundleID).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                SizePill(bytes: group.totalSize, prominent: true)

                Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }

            if expanded {
                Divider().padding(.leading, 14)
                VStack(spacing: 0) {
                    ForEach(group.files) { file in
                        HStack(spacing: 10) {
                            Button { model.toggleLeftoverFile(group: group, file: file) } label: {
                                SelectCircle(isOn: file.isSelected)
                            }.buttonStyle(.plain)
                            Text(file.displayPath).font(.system(size: 11))
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .help(file.url.path)
                            Spacer(minLength: 8)
                            Text(Format.size(file.sizeBytes))
                                .font(.system(size: 10.5, design: .rounded)).monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.05)))
    }
}
