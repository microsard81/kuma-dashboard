import SwiftUI

/// A view that displays sections side-by-side with draggable dividers
/// between columns. Column widths are persisted in UserDefaults.
struct ResizableColumnsView<Content: View>: View {
    let sections: [String]
    @Binding var columnWidths: [CGFloat]
    let totalWidth: CGFloat
    let content: (String) -> Content

    private let dividerWidth: CGFloat = 6
    private let minColumnWidth: CGFloat = 120

    private var effectiveWidths: [CGFloat] {
        let count = sections.count
        guard count > 0 else { return [] }
        let availableWidth = totalWidth - dividerWidth * CGFloat(count - 1)

        if columnWidths.count == count {
            // Normalize to fit available width
            let total = columnWidths.reduce(0, +)
            if total > 0 {
                return columnWidths.map { $0 / total * availableWidth }
            }
        }
        // Equal distribution
        let w = availableWidth / CGFloat(count)
        return Array(repeating: w, count: count)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                content(section)
                    .frame(width: effectiveWidths.indices.contains(index) ? effectiveWidths[index] : nil)
                    .clipped()

                if index < sections.count - 1 {
                    ResizableDivider(
                        leftWidth: effectiveWidths.indices.contains(index) ? effectiveWidths[index] : 100,
                        onDrag: { delta in
                            resizeColumns(at: index, delta: delta)
                        },
                        onDragEnd: {
                            saveWidths()
                        }
                    )
                }
            }
        }
    }

    private func resizeColumns(at index: Int, delta: CGFloat) {
        let count = sections.count
        var widths = effectiveWidths

        guard index < count - 1 else { return }

        let newLeft = widths[index] + delta
        let newRight = widths[index + 1] - delta

        // Enforce minimum
        guard newLeft >= minColumnWidth && newRight >= minColumnWidth else { return }

        widths[index] = newLeft
        widths[index + 1] = newRight

        columnWidths = widths
    }

    private func saveWidths() {
        UserDefaults.standard.set(columnWidths, forKey: "mac_column_widths")
    }
}

/// A draggable divider between two columns.
private struct ResizableDivider: View {
    let leftWidth: CGFloat
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    @State private var isDragging = false
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.2))
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let delta = value.translation.width - lastTranslation
                        lastTranslation = value.translation.width
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastTranslation = 0
                        onDragEnd()
                    }
            )
    }
}
