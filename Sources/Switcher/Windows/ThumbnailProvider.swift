import AppKit
@preconcurrency import ScreenCaptureKit

/// Window previews via ScreenCaptureKit. The previous capture of each window is shown at once,
/// then replaced by a fresh one a moment later.
@MainActor
final class ThumbnailProvider {
    /// Pixel size the previews are captured at (2× the card's preview area)
    nonisolated static let captureSize = CGSize(width: 408, height: 248)

    private var cache: [CGWindowID: NSImage] = [:]
    private var generation = 0

    func cached(for items: [WindowItem]) -> [CGWindowID: NSImage] {
        var result: [CGWindowID: NSImage] = [:]
        for id in items.compactMap(\.windowID) {
            result[id] = cache[id]
        }
        return result
    }

    func refresh(_ items: [WindowItem], update: @escaping @MainActor (CGWindowID, NSImage) -> Void) {
        guard Permissions.screenRecording else { return }
        let ids = Set(items.compactMap(\.windowID))
        generation += 1
        let current = generation

        Task { @MainActor in
            // Minimized windows and other Spaces aren't "on screen" but can often still be captured
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            let targets = content.windows.filter { ids.contains($0.windowID) }

            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for window in targets {
                    group.addTask {
                        (window.windowID, await Self.capture(window))
                    }
                }
                for await (id, image) in group {
                    guard let image else { continue }
                    self.store(image, for: id, generation: current, update: update)
                }
            }

            // Forget windows that no longer exist
            if current == generation {
                cache = cache.filter { ids.contains($0.key) }
            }
        }
    }

    /// Each preview appears as soon as it's captured, unless a newer opening superseded this one
    private func store(_ image: CGImage, for id: CGWindowID, generation: Int, update: @MainActor (CGWindowID, NSImage) -> Void) {
        guard generation == self.generation else { return }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
        cache[id] = thumbnail
        update(id, thumbnail)
    }

    nonisolated private static func capture(_ window: SCWindow) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }

        let scale = min(captureSize.width / frame.width, captureSize.height / frame.height, 2)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(frame.width * scale))
        configuration.height = max(1, Int(frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
