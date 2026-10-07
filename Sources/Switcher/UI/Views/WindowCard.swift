import SwiftUI

struct WindowCard: View {
    let item: WindowItem
    let thumbnail: NSImage?
    let icon: NSImage
    let isSelected: Bool
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .frame(height: 128)

            HStack(spacing: 7) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(item.isWindowless ? "Aucune fenêtre ouverte" : item.appName)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .frame(width: SwitcherController.cardWidth, height: SwitcherController.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.16 : (isHovered ? 0.09 : 0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(isHovered ? 0.3 : 0.1),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if isHovered || isSelected {
                CloseButton(isWindowless: item.isWindowless, action: onClose)
                    .offset(x: 7, y: -7)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.2), radius: isSelected ? 10 : 4, x: 0, y: isSelected ? 4 : 2)
        .scaleEffect(isHovered && !isSelected ? 1.015 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.28))

            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                        .padding(6)
                        .opacity(item.isMinimized || item.isHidden ? 0.55 : 1)
                } else {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .opacity(item.isWindowless ? 0.7 : 0.9)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let badge {
                HStack(spacing: 4) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 8.5, weight: .bold))
                    Text(badge.label)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .padding(7)
            }
        }
    }

    private var badge: (symbol: String, label: String)? {
        if item.isWindowless { return ("macwindow.badge.plus", "Aucune fenêtre") }
        if item.isMinimized { return ("minus.circle.fill", "Réduite") }
        if item.isHidden { return ("eye.slash.fill", "Masquée") }
        return nil
    }
}

/// Windows 11-style × in the card's corner
private struct CloseButton: View {
    let isWindowless: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isHovered ? Color.red : Color.black.opacity(0.75)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isWindowless ? "Quitter l'app (Q)" : "Fermer la fenêtre (W)")
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
