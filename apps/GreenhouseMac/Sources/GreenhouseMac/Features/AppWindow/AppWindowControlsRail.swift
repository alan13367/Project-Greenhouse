import AppKit
import CoreVideo
import GreenhouseCore
import GreenhouseRuntime
import SwiftUI
import UniformTypeIdentifiers

struct AppWindowControlsRail: View {
    let app: AndroidApp
    let session: AppStreamSession?
    let canReconnect: Bool
    @Binding var isCollapsed: Bool
    @Binding var metricsVisible: Bool
    let focus: () -> Void
    let reconnect: () -> Void
    let toggleFullScreen: () -> Void
    let close: () -> Void

    var body: some View {
        expandedControls
    }

    private var expandedControls: some View {
        VStack(spacing: 9) {
            ControlButton(
                title: "Hide Controls",
                systemImage: "sidebar.right",
                action: { isCollapsed = true }
            )

            RailDivider()

            ControlButton(
                title: "Back",
                systemImage: "chevron.backward",
                isEnabled: session != nil,
                action: { session?.pressAndroidKey(.back) }
            )
            ControlButton(
                title: "Home",
                systemImage: "house",
                isEnabled: session != nil,
                action: { session?.pressAndroidKey(.home) }
            )
            ControlButton(
                title: "App Switch",
                systemImage: "rectangle.on.rectangle",
                isEnabled: session != nil,
                action: { session?.pressAndroidKey(.appSwitch) }
            )

            RailDivider()

            ControlButton(
                title: "Focus App",
                systemImage: "scope",
                action: focus
            )
            ControlButton(
                title: "Reconnect Stream",
                systemImage: "arrow.triangle.2.circlepath",
                isEnabled: canReconnect,
                action: reconnect
            )
            ControlButton(
                title: "Toggle Full Screen",
                systemImage: "arrow.up.left.and.arrow.down.right",
                action: toggleFullScreen
            )
            ControlButton(
                title: metricsVisible ? "Hide Metrics" : "Show Metrics",
                systemImage: "speedometer",
                isSelected: metricsVisible,
                action: { metricsVisible.toggle() }
            )

            RailDivider()

            ControlButton(
                title: "Save Screenshot",
                systemImage: "camera",
                isEnabled: currentFrame != nil,
                action: saveScreenshot
            )
            ControlButton(
                title: "Paste Text",
                systemImage: "doc.on.clipboard",
                isEnabled: session != nil,
                action: pasteText
            )
            ControlButton(
                title: isMuted ? "Unmute" : "Mute",
                systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isEnabled: session != nil,
                isSelected: isMuted,
                action: { session?.setMuted(!isMuted) }
            )

            RailDivider()

            ControllerStatusView(session: session)

            RailDivider()

            ControlButton(
                title: "Close Window",
                systemImage: "xmark",
                role: .destructive,
                action: close
            )
        }
        .padding(.vertical, 8)
        .frame(width: 54)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.separator.opacity(0.5))
                .frame(width: 1)
        }
    }

    private var currentFrame: CVPixelBuffer? {
        session?.model.pixelBuffer
    }

    private var isMuted: Bool {
        session?.model.isMuted ?? false
    }

    private func saveScreenshot() {
        guard let currentFrame else { return }
        do {
            let data = try AppStreamScreenshotExporter.pngData(from: currentFrame)
            try AppWindowFilePanels.savePNG(
                data,
                suggestedName: "\(app.name) Screenshot.png"
            )
        } catch {
            AppWindowFilePanels.presentError(
                error,
                title: "Screenshot could not be saved"
            )
        }
    }

    private func pasteText() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            return
        }
        session?.text(text)
    }
}

struct CollapsedAppWindowControlsButton: View {
    @Binding var isCollapsed: Bool

    var body: some View {
        Button {
            isCollapsed = false
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 38, height: 38)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .help("Show Controls")
        .accessibilityLabel("Show Controls")
    }
}

private struct RailDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.6))
            .frame(width: 28, height: 1)
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isEnabled = true
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.accentColor.opacity(0.28) : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ControllerStatusView: View {
    let session: AppStreamSession?

    var body: some View {
        Image(systemName: connected ? "gamecontroller.fill" : "gamecontroller")
            .font(.system(size: 16, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(connected ? Color.accentColor : Color.secondary)
            .frame(width: 34, height: 34)
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var connected: Bool {
        session?.model.controllerConnected ?? false
    }

    private var helpText: String {
        guard let model = session?.model else {
            return "Controller status unavailable"
        }
        guard model.controllerConnected else {
            return "No controller connected"
        }
        let name = model.controllerName ?? "Controller"
        return model.controllerFocused
            ? "\(name) routed to this app"
            : "\(name) connected"
    }
}

@MainActor
private enum AppWindowFilePanels {
    static func savePNG(_ data: Data, suggestedName: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = sanitizedFileName(suggestedName)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    static func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let scalars = name.unicodeScalars.map { scalar in
            invalid.contains(scalar) ? "-" : String(scalar)
        }
        let sanitized = scalars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Greenhouse Screenshot.png" : sanitized
    }
}
