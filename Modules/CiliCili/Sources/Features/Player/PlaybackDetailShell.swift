import SwiftUI

struct PlaybackDetailScrollAdjustment: Equatable {
    let offset: CGFloat
    let token: Int
}

struct PlaybackDetailScrollPage<Content: View>: View {
    let layoutWidth: CGFloat
    let topInset: CGFloat
    let background: Color
    var scrollAdjustment: PlaybackDetailScrollAdjustment?
    let onScrollOffsetChange: ((CGFloat) -> Void)?
    let content: () -> Content

    @State private var scrollPosition = ScrollPosition()
    @State private var appliedScrollAdjustmentToken = 0

    init(
        layoutWidth: CGFloat,
        topInset: CGFloat,
        background: Color = Color(.systemGroupedBackground),
        scrollAdjustment: PlaybackDetailScrollAdjustment? = nil,
        onScrollOffsetChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.layoutWidth = layoutWidth
        self.topInset = topInset
        self.background = background
        self.scrollAdjustment = scrollAdjustment
        self.onScrollOffsetChange = onScrollOffsetChange
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset)

                content()
                    .frame(width: layoutWidth, alignment: .top)
            }
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .nativeTopScrollEdgeEffect()
        .modifier(PlaybackDetailScrollOffsetObserver(onChange: onScrollOffsetChange))
        .onAppear {
            applyScrollAdjustment(scrollAdjustment)
        }
        .onChange(of: scrollAdjustment) { _, adjustment in
            applyScrollAdjustment(adjustment)
        }
        .frame(width: layoutWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(background)
    }

    private func applyScrollAdjustment(_ adjustment: PlaybackDetailScrollAdjustment?) {
        guard let adjustment, adjustment.token != appliedScrollAdjustmentToken else { return }
        appliedScrollAdjustmentToken = adjustment.token
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition.scrollTo(y: max(0, adjustment.offset))
        }
    }
}

private struct PlaybackDetailScrollOffsetObserver: ViewModifier {
    let onChange: ((CGFloat) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onChange {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                onChange(offset)
            }
        } else {
            content
        }
    }
}

struct PlaybackDetailPlayerStage<Content: View, Player: View>: View {
    let screenSize: CGSize
    let showsContent: Bool
    let contentOpacity: Double
    let allowsContentHitTesting: Bool
    let showsFullscreenBackdrop: Bool
    let background: Color
    let content: () -> Content
    let player: () -> Player

    init(
        screenSize: CGSize,
        showsContent: Bool = true,
        contentOpacity: Double = 1,
        allowsContentHitTesting: Bool = true,
        showsFullscreenBackdrop: Bool = false,
        background: Color = Color(.systemGroupedBackground),
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder player: @escaping () -> Player
    ) {
        self.screenSize = screenSize
        self.showsContent = showsContent
        self.contentOpacity = contentOpacity
        self.allowsContentHitTesting = allowsContentHitTesting
        self.showsFullscreenBackdrop = showsFullscreenBackdrop
        self.background = background
        self.content = content
        self.player = player
    }

    var body: some View {
        ZStack(alignment: .top) {
            background
                .opacity(showsFullscreenBackdrop ? 0 : 1)
                .ignoresSafeArea()

            if showsContent {
                content()
                    .frame(width: screenSize.width, height: screenSize.height, alignment: .top)
                    .opacity(contentOpacity)
                    .allowsHitTesting(allowsContentHitTesting)
            }

            if showsFullscreenBackdrop {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            player()
                .zIndex(1)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}
