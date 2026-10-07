import AppKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var accessibility = Permissions.accessibility
    @Published var screenRecording = Permissions.screenRecording
    @Published var isActive = SwitcherController.shared.isEnabled

    private var poll: Timer?

    func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        accessibility = Permissions.accessibility
        screenRecording = Permissions.screenRecording
        // Takes over ⌘Tab the moment Accessibility is granted, no relaunch needed
        SwitcherController.shared.enableIfPossible()
        isActive = SwitcherController.shared.isEnabled
    }
}

/// First-launch window explaining the two permissions, in Stack's style
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    private let model = OnboardingModel()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let panel = OnboardingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named: .darkAqua)

            let hostingView = NSHostingView(rootView: OnboardingView(model: model) { [weak self] in self?.close() })
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 26
            hostingView.layer?.cornerCurve = .continuous
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView
            panel.setContentSize(hostingView.fittingSize)
            self.panel = panel
        }

        model.refresh()
        model.startPolling()
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        model.stopPolling()
        panel?.orderOut(nil)
    }
}

private final class OnboardingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        OnboardingController.shared.close()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("SWITCHER")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(7)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("⌘Tab, fenêtre par fenêtre")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                Text("Comme Alt-Tab sous Windows : chaque fenêtre a sa propre vignette — votre brouillon Thunderbird, chacune de vos fenêtres Chrome…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PermissionRow(
                symbol: "hand.raised.fill",
                title: "Accessibilité",
                detail: "Obligatoire. Pour intercepter ⌘Tab et amener la bonne fenêtre au premier plan.",
                isGranted: model.accessibility,
                action: Permissions.requestAccessibility
            )

            PermissionRow(
                symbol: "rectangle.dashed.badge.record",
                title: "Enregistrement de l'écran",
                detail: "Facultatif. Pour les aperçus des fenêtres. macOS proposera ensuite de relancer Switcher.",
                isGranted: model.screenRecording,
                action: Permissions.requestScreenRecording
            )

            HStack(spacing: 8) {
                Image(systemName: model.isActive ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundColor(model.isActive ? .green : .secondary)
                    .font(.system(size: 12))
                Text(model.isActive
                     ? "C'est prêt : maintenez ⌘ et appuyez sur Tab pour essayer."
                     : "Tant que l'Accessibilité n'est pas accordée, ⌘Tab garde son comportement macOS habituel.")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(action: onClose) {
                    Text("Terminé")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .hudBackground()
        .animation(.easeInOut(duration: 0.2), value: model.accessibility)
        .animation(.easeInOut(duration: 0.2), value: model.screenRecording)
        .animation(.easeInOut(duration: 0.2), value: model.isActive)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isGranted {
                Label("Autorisé", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text("Autoriser")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isGranted ? Color.green.opacity(0.35) : Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}
