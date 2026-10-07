import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onSizeChange: (CGSize) -> Void
    let onHover: (Int) -> Void
    let onClick: (Int) -> Void
    let onClose: (Int) -> Void

    private var gridWidth: CGFloat {
        let columns = CGFloat(max(model.columns, 1))
        return columns * SwitcherController.cardWidth + (columns - 1) * SwitcherController.cardSpacing
    }

    /// Wide enough for the shortcut bar even with a single window
    private var contentWidth: CGFloat {
        max(gridWidth, 600)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            grid
            hintBar
        }
        .padding(20)
        .hudBackground()
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onSizeChange(size)
        }
    }

    // MARK: - Header: full title of the selected window

    private var header: some View {
        HStack(spacing: 8) {
            if let item = model.selectedItem {
                Image(nsImage: model.icon(for: item.pid))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)

                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                if !item.isWindowless, !item.title.isEmpty {
                    Text("— \(item.appName)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: contentWidth, height: 22)
    }

    // MARK: - Cards

    @ViewBuilder
    private var grid: some View {
        let rows = model.rows
        let cards = VStack(spacing: SwitcherController.cardSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: SwitcherController.cardSpacing) {
                    ForEach(row, id: \.element.id) { entry in
                        card(for: entry.element, at: entry.offset)
                    }
                }
            }
        }
        .frame(width: contentWidth)

        if rows.count > model.maxVisibleRows {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    cards.padding(.vertical, 6)
                }
                .frame(width: contentWidth, height: CGFloat(model.maxVisibleRows) * (SwitcherController.cardHeight + SwitcherController.cardSpacing))
                .onChange(of: model.selectedIndex) { _, index in
                    if let id = model.items.indices.contains(index) ? model.items[index].id : nil {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        } else {
            cards
        }
    }

    private func card(for item: WindowItem, at index: Int) -> some View {
        WindowCard(
            item: item,
            thumbnail: item.windowID.flatMap { model.thumbnails[$0] },
            icon: model.icon(for: item.pid),
            isSelected: index == model.selectedIndex,
            onClose: { onClose(index) }
        )
        .id(item.id)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering in
            if hovering { onHover(index) }
        }
        .onTapGesture {
            onClick(index)
        }
    }

    // MARK: - Shortcuts

    private var hintBar: some View {
        HStack(spacing: 12) {
            ShortcutHint(key: "⇥", label: "Suivante")
            ShortcutHint(key: "⇧⇥", label: "Précédente")
            ShortcutHint(key: "← →", label: "Naviguer")
            ShortcutHint(key: "W", label: "Fermer")
            ShortcutHint(key: "Q", label: "Quitter l'app")
            ShortcutHint(key: "⎋", label: "Annuler")

            Spacer(minLength: 8)

            Text(model.items.count == 1 ? "1 fenêtre" : "\(model.items.count) fenêtres")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(width: contentWidth)
    }
}
