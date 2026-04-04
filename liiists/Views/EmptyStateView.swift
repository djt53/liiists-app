import SwiftUI

struct EmptyStateView: View {
    var onCreateList: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Theme.spaceLG) {
            Spacer()

            // Dot-grid decoration
            DotGrid()
                .frame(width: 96, height: 96)
                .opacity(0.3)

            Text("NO LISTS YET")
                .font(Theme.headingFont(size: Theme.subheadingSize, weight: .medium))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .tracking(Theme.subheadingSize * 0.04)

            Text("Create your first list to get started.")
                .font(Theme.bodyFont(size: Theme.bodySM))
                .foregroundStyle(Theme.ndTextDisabled.resolve(for: colorScheme))

            Spacer().frame(height: Theme.spaceSM)

            // Nothing primary button — pill, white bg, black text, Space Mono ALL CAPS
            Button(action: onCreateList) {
                Text("CREATE A LIST")
                    .font(Theme.labelFont(size: 13))
                    .tracking(13 * 0.06)
                    .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                    .padding(.horizontal, Theme.spaceLG)
                    .frame(height: Theme.buttonMinHeight)
                    .background(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ndBlack.resolve(for: colorScheme))
    }
}

// MARK: - Dot Grid Motif

struct DotGrid: View {
    let columns = 6
    let rows = 6
    let dotSize: CGFloat = 2
    let spacing: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let totalWidth = CGFloat(columns - 1) * spacing
            let totalHeight = CGFloat(rows - 1) * spacing
            let offsetX = (size.width - totalWidth) / 2
            let offsetY = (size.height - totalHeight) / 2

            for row in 0..<rows {
                for col in 0..<columns {
                    let x = offsetX + CGFloat(col) * spacing
                    let y = offsetY + CGFloat(row) * spacing
                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(hex: 0x333333))
                    )
                }
            }
        }
    }
}
