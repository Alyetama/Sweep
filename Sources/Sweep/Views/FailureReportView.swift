import SwiftUI

/// Explains, item by item, why something is still on disk after a cleanup. Shown
/// as a sheet so it stays put until dismissed, unlike the success toast.
struct FailureReportView: View {
    let report: FailureReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 580, height: 400)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: 0xFF9F0A))
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 item wasn't removed" : "\(count) items weren't removed")
                    .font(.system(size: 16, weight: .semibold))
                Text("Everything else went to the Trash. These are still on disk:")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(report.failures.enumerated()), id: \.element.id) { index, failure in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(failure.displayPath)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                                .help(failure.url.path)
                            Spacer(minLength: 8)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([failure.url])
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                        Text(failure.reason)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    if index < report.failures.count - 1 {
                        Divider().padding(.leading, 22)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if report.needsFullDiskAccess {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var count: Int { report.failures.count }
}
