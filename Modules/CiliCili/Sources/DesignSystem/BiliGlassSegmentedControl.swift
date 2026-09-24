import SwiftUI

struct BiliGlassSegmentedControl<Option: Identifiable & Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let options: [Option]
    let selected: Option
    let title: (Option) -> String
    let select: (Option) -> Void
    var showsContainer = true
    var animation: Animation = .smooth(duration: 0.28)

    private var activeAnimation: Animation? {
        reduceMotion ? nil : animation
    }

    @ViewBuilder
    var body: some View {
        if showsContainer {
            controlContent
                .biliBottomTabGlassEffect(interactive: false, in: Capsule())
        } else {
            controlContent
        }
    }

    private var controlContent: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 3
            let contentWidth = max(proxy.size.width - inset * 2, 0)
            let segmentWidth = contentWidth / CGFloat(max(options.count, 1))

            ZStack(alignment: .topLeading) {
                if let selectedIndex {
                    Capsule()
                        .fill(selectedFill)
                        .frame(width: segmentWidth, height: 34)
                        .offset(
                            x: inset + CGFloat(selectedIndex) * segmentWidth,
                            y: 3
                        )
                        .animation(activeAnimation, value: selectedIndex)
                }

                HStack(spacing: 0) {
                    ForEach(options) { option in
                        segmentButton(for: option)
                            .frame(width: segmentWidth)
                    }
                }
                .frame(width: contentWidth, height: 40)
                .offset(x: inset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(height: 40)
        .accessibilityElement(children: .contain)
    }

    private var selectedIndex: Int? {
        options.firstIndex(of: selected)
    }

    private var selectedFill: Color {
        Color.primary.opacity(0.12)
    }

    private func segmentButton(for option: Option) -> some View {
        let isSelected = option == selected

        return Button {
            guard !isSelected else { return }
            withAnimation(activeAnimation) {
                select(option)
            }
        } label: {
            Text(title(option))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Color.primary.opacity(isSelected ? 1 : 0.72))
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 40)
        .accessibilityLabel(title(option))
        .accessibilityValue(isSelected ? "已选中" : "")
    }
}
