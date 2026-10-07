import AppKit

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var items: [WindowItem] = []
    @Published var selectedIndex = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var columns = 1
    @Published var maxVisibleRows = 3

    private var icons: [pid_t: NSImage] = [:]

    var selectedItem: WindowItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    /// Items with their index, cut into grid rows
    var rows: [[(offset: Int, element: WindowItem)]] {
        let indexed = Array(items.enumerated())
        return stride(from: 0, to: indexed.count, by: max(columns, 1)).map { start in
            Array(indexed[start..<min(start + columns, indexed.count)])
        }
    }

    func icon(for pid: pid_t) -> NSImage {
        if let cached = icons[pid] {
            return cached
        }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
        icons[pid] = icon
        return icon
    }

    func forgetIcons() {
        icons.removeAll()
    }
}
