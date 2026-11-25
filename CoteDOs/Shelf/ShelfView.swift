import SwiftUI

struct ShelfView: View {
    @ObservedObject var shelf: FileShelfModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if shelf.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 25, weight: .light))
                    Text("拖放文件到这里暂存")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(NotchStyle.secondary)
            } else {
                // `minWidth: geo.size.width` is what centres the row. A plain
                // horizontal `ScrollView` lays its content out from the leading
                // edge, so four files sat hard left with half the page empty
                // beside them — and it still scrolls the moment they outgrow it.
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, shelf: shelf)
                            }
                        }
                        .padding(6)
                        .frame(minWidth: geo.size.width, alignment: .center)
                    }
                    .frame(height: geo.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(shelf.isDropTargeted ? 0.10 : 0.055),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(shelf.isDropTargeted ? Color.accentColor
                              : .white.opacity(contrast == .increased ? 0.26 : 0.10),
                              style: StrokeStyle(lineWidth: shelf.isDropTargeted ? 1.5 : 0.75,
                                                 dash: shelf.isDropTargeted ? [5, 4] : []))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if !shelf.items.isEmpty {
                Button("清空暂存", systemImage: "trash", action: shelf.clear)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11))
                    .buttonStyle(NotchButtonStyle(shape: .circle(28)))
                    .help("清空暂存")
                    .padding(8)
            }
        }
    }
}

private struct ShelfItemView: View {
    @ObservedObject var item: ShelfItem
    @ObservedObject var shelf: FileShelfModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 46, height: 46)
            .overlay(alignment: .topTrailing) {
                if item.isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                }
            }

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(9)
        .background(.white.opacity(hovering ? 0.13 : 0.075),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.65)
                .allowsHitTesting(false)
        }
        .offset(y: hovering && !reduceMotion ? -2 : 0)
        .opacity(item.isMissing ? 0.55 : 1)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
        .help(item.isMissing
              ? "原文件已不存在" + " — " + item.name
              : item.name)
        .onDrag {
            // Don't hand over a file that no longer exists.
            guard shelf.refreshExistence(of: item) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            ShareLink(item: item.url) {
                Label("共享…", systemImage: "square.and.arrow.up")
            }
            Button("移除", role: .destructive) { shelf.remove(item) }
        }
    }
}
