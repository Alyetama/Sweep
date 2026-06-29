import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 208, ideal: 224, max: 260)
        } detail: {
            Group {
                switch model.section {
                case .uninstaller: UninstallerView()
                case .leftovers:   LeftoversView()
                }
            }
            .frame(minWidth: 680)
        }
        .navigationTitle("")
        // Result toast + confirmation/admin dialogs live at the top level so they
        // overlay either section.
        .overlay(alignment: .bottom) { resultToast }
        .alert(item: $model.pendingConfirm) { pending in
            Alert(
                title: Text(pending.title),
                message: Text("\(pending.message)\n\nFrees \(Format.size(pending.bytes))."),
                primaryButton: .destructive(Text("Move to Trash")) { model.performPendingRemoval() },
                secondaryButton: .cancel()
            )
        }
        // The admin prompt is hosted on a separate (clear) background view —
        // SwiftUI only presents one `.alert` per view, so stacking it on the same
        // view as the confirmation alert above would silently suppress one of them.
        .background(adminAlertHost)
    }

    private var adminAlertHost: some View {
        Color.clear
            .alert(item: $model.adminPrompt) { prompt in
                Alert(
                    title: Text("Some items need administrator access"),
                    message: Text("\(prompt.urls.count) protected item\(prompt.urls.count == 1 ? "" : "s") (\(Format.size(prompt.bytes))) couldn't be moved to the Trash. Remove them with your password?"),
                    primaryButton: .destructive(Text("Remove…")) { model.performAdminRemoval() },
                    secondaryButton: .cancel(Text("Skip"))
                )
            }
    }

    @ViewBuilder
    private var resultToast: some View {
        if let result = model.result {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title).font(.system(size: 13, weight: .semibold))
                    Text("Freed \(Format.size(result.freedBytes)) • \(result.removedCount) item\(result.removedCount == 1 ? "" : "s")"
                         + (result.failedCount > 0 ? " • \(result.failedCount) skipped" : ""))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: result.id) {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                withAnimation(.spring(response: 0.4)) { model.result = nil }
            }
        }
    }
}
