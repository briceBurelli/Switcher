import AppKit
@preconcurrency import ScreenCaptureKit
import os

/// SwitcherDebug only: photographs the screen area under the panel, exactly as composited
enum DebugScreen {
    static func capture(_ rect: NSRect) {
        Task {
            let log = Logger(subsystem: "com.stack.switcher", category: "debug")
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { NSRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height).intersects(rect) }) ?? content.displays.first else { return }
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: screenHeight - rect.maxY - display.frame.minY, width: rect.width, height: rect.height)
            configuration.width = Int(rect.width)
            configuration.height = Int(rect.height)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                log.notice("[debug] screen capture failed")
                return
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("switcher-screen.png")
            try? data.write(to: url)
            log.notice("[debug] screen under panel saved to \(url.path, privacy: .public)")
        }
    }
}
