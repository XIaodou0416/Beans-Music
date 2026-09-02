import SwiftUI

private struct RecordRotationState: Equatable, Sendable {
    static let defaultDegreesPerSecond: Double = 24.0

    let degreesPerSecond: Double
    private(set) var isAnimating: Bool = false
    private var baseAngle: Double = 0.0
    private var startedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    private var stoppedAngle: Double = 0.0

    init(degreesPerSecond: Double = Self.defaultDegreesPerSecond) {
        self.degreesPerSecond = degreesPerSecond
    }

    mutating func start(at date: Date = Date()) {
        guard !isAnimating else { return }
        baseAngle = stoppedAngle
        startedAt = date
        isAnimating = true
    }

    mutating func stop(at date: Date = Date(), extraTravelDegrees: Double = 0) {
        guard isAnimating else { return }
        stoppedAngle = currentAngle(at: date) + extraTravelDegrees
        isAnimating = false
    }

    func currentAngle(at date: Date) -> Double {
        guard isAnimating else { return stoppedAngle }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return baseAngle + elapsed * degreesPerSecond
    }

    mutating func reset(to angle: Double = 0) {
        baseAngle = angle
        stoppedAngle = angle
        isAnimating = false
    }
}

struct VinylTurntableView: View {
    let coverURL: URL?
    let isPlaying: Bool
    let trackId: Int?
    let size: CGFloat
    var onTap: (() -> Void)? = nil
    var onNextTrack: (() -> Void)? = nil
    var onPreviousTrack: (() -> Void)? = nil

    @State private var rotationState = RecordRotationState()
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isTransitioningTrack = false

    var body: some View {
        let discSize = size
        let armHeight = discSize * 0.68
        let stageWidth = discSize + 48
        let stageHeight = discSize + armHeight * 0.38

        return ZStack(alignment: .top) {
            TimelineView(.animation(paused: !isPlaying || isDragging || isTransitioningTrack)) { timeline in
                let currentAngle = rotationState.currentAngle(at: timeline.date)
                VinylRecordView(coverURL: coverURL, size: discSize)
                    .rotationEffect(.degrees(currentAngle))
            }
            .offset(x: dragOffset)
            .padding(.top, armHeight * 0.36)
            .contentShape(Circle())
            .gesture(dragAndSwipeGesture(discSize: discSize))
            .onTapGesture { onTap?() }
            .zIndex(1)

            VinylTonearmView(
                isPlaying: isPlaying && !isDragging && !isTransitioningTrack,
                height: armHeight
            )
            .offset(x: discSize * 0.12, y: -armHeight * 0.08)
            .allowsHitTesting(false)
            .zIndex(2)
        }
        .frame(width: stageWidth, height: stageHeight, alignment: .top)
        .onAppear {
            if isPlaying { rotationState.start(at: Date()) }
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                rotationState.start(at: Date())
            } else {
                rotationState.stop(at: Date())
            }
        }
        .onChange(of: trackId) { _ in
            isTransitioningTrack = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                isTransitioningTrack = false
            }
        }
    }

    private func dragAndSwipeGesture(discSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) * 0.6 {
                    isDragging = true
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let translation = value.translation.width
                let velocity = value.predictedEndTranslation.width
                let swipeThreshold: CGFloat = 45

                if translation < -swipeThreshold || velocity < -100 {
                    withAnimation(.easeOut(duration: 0.20)) {
                        dragOffset = -discSize * 1.25
                    }
                    onNextTrack?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        dragOffset = discSize * 1.25
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                            dragOffset = 0
                            isDragging = false
                        }
                    }
                } else if translation > swipeThreshold || velocity > 100 {
                    withAnimation(.easeOut(duration: 0.20)) {
                        dragOffset = discSize * 1.25
                    }
                    onPreviousTrack?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        dragOffset = -discSize * 1.25
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                            dragOffset = 0
                            isDragging = false
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
            }
    }
}

struct VinylRecordView: View {
    let coverURL: URL?
    let size: CGFloat

    var body: some View {
        let discDiameter = size
        let labelDiameter = discDiameter * 0.64
        let spindleHoleDiameter = max(7, discDiameter * 0.032)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.06), Color(white: 0.02)],
                        center: .center,
                        startRadius: discDiameter * 0.3,
                        endRadius: discDiameter * 0.5
                    )
                )
                .frame(width: discDiameter + 6, height: discDiameter + 6)
                .shadow(color: .black.opacity(0.45), radius: max(16, discDiameter * 0.08), x: 0, y: discDiameter * 0.04)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.14), Color(white: 0.08), Color(white: 0.05), Color(white: 0.03)],
                        center: .center,
                        startRadius: discDiameter * 0.25,
                        endRadius: discDiameter * 0.5
                    )
                )
                .frame(width: discDiameter, height: discDiameter)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.04), Color.white.opacity(0.18), Color.black.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }

            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.06), Color(white: 0.18), Color(white: 0.05), Color(white: 0.22),
                            Color(white: 0.07), Color(white: 0.16), Color(white: 0.05), Color(white: 0.20),
                            Color(white: 0.06), Color(white: 0.18), Color(white: 0.06)
                        ]),
                        center: .center
                    )
                )
                .frame(width: discDiameter - 4, height: discDiameter - 4)
                .opacity(0.9)

            ForEach(0..<18, id: \.self) { i in
                let factor = 0.68 + (Double(i) / 17.0) * 0.29
                let isMajorTrack = (i % 4 == 0)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(isMajorTrack ? 0.14 : 0.06), Color.black.opacity(0.4), Color.white.opacity(isMajorTrack ? 0.09 : 0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isMajorTrack ? 0.8 : 0.45
                    )
                    .frame(width: discDiameter * factor, height: discDiameter * factor)
            }

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                .frame(width: discDiameter * 0.98, height: discDiameter * 0.98)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.black.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: discDiameter * 0.665, height: discDiameter * 0.665)

            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.02), location: 0.08),
                            .init(color: Color.white.opacity(0.18), location: 0.14),
                            .init(color: Color(red: 0.85, green: 0.95, blue: 1.0).opacity(0.24), location: 0.17),
                            .init(color: Color.white.opacity(0.18), location: 0.20),
                            .init(color: Color.white.opacity(0.02), location: 0.26),
                            .init(color: .clear, location: 0.34),
                            .init(color: .clear, location: 0.50),
                            .init(color: Color.white.opacity(0.02), location: 0.58),
                            .init(color: Color.white.opacity(0.18), location: 0.64),
                            .init(color: Color(red: 0.85, green: 0.95, blue: 1.0).opacity(0.24), location: 0.67),
                            .init(color: Color.white.opacity(0.18), location: 0.70),
                            .init(color: Color.white.opacity(0.02), location: 0.76),
                            .init(color: .clear, location: 0.84),
                            .init(color: .clear, location: 1.0)
                        ]),
                        center: .center,
                        angle: .degrees(35)
                    )
                )
                .frame(width: discDiameter - 2, height: discDiameter - 2)
                .blendMode(.screen)
                .allowsHitTesting(false)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: labelDiameter + 6, height: labelDiameter + 6)
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)

                Group {
                    if coverURL != nil {
                        CoverImage(url: coverURL, size: labelDiameter, cornerRadius: labelDiameter / 2, emptyHint: nil)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(white: 0.22), Color(white: 0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: labelDiameter * 0.35, weight: .light))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(width: labelDiameter, height: labelDiameter)
                    }
                }
                .frame(width: labelDiameter, height: labelDiameter)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5)
                }

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                    .frame(width: labelDiameter * 0.86, height: labelDiameter * 0.86)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.65), Color(white: 0.90), Color(white: 0.40)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: spindleHoleDiameter * 1.8, height: spindleHoleDiameter * 1.8)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)

                Circle()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: spindleHoleDiameter, height: spindleHoleDiameter)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: spindleHoleDiameter * 0.55, height: spindleHoleDiameter * 0.55)
                    .offset(x: -spindleHoleDiameter * 0.12, y: -spindleHoleDiameter * 0.12)
            }
            .frame(width: labelDiameter, height: labelDiameter)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: discDiameter * 0.92, height: discDiameter * 0.92)
                .blendMode(.screen)
        }
        .frame(width: discDiameter, height: discDiameter)
    }
}

struct VinylTonearmView: View {
    let isPlaying: Bool
    let height: CGFloat
    let reduceMotion: Bool

    init(isPlaying: Bool, height: CGFloat = 175, reduceMotion: Bool = false) {
        self.isPlaying = isPlaying
        self.height = height
        self.reduceMotion = reduceMotion
    }

    var body: some View {
        let width = height * 0.58
        let pivotSize = width * 0.46

        ZStack(alignment: .top) {
            pivotBase(size: pivotSize)
                .zIndex(3)

            TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                let wobble = wobbleDegrees(at: timeline.date)
                armAssembly(width: width, height: height)
                    .rotationEffect(
                        .degrees(rotationAngle + wobble),
                        anchor: UnitPoint(x: 0.5, y: pivotSize * 0.5 / height)
                    )
            }
            .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.74, blendDuration: 0.08), value: isPlaying)
            .shadow(color: .black.opacity(0.4), radius: 6, x: -3, y: 5)
            .zIndex(2)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private var rotationAngle: Double { isPlaying ? 0.0 : -32.0 }

    private func wobbleDegrees(at date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return 0 }
        let seconds = date.timeIntervalSinceReferenceDate
        let harmonic1 = sin(seconds * 2.0 * .pi / 3.2) * 0.20
        let harmonic2 = sin(seconds * 2.0 * .pi / 1.1 + 0.6) * 0.08
        return harmonic1 + harmonic2
    }

    private func pivotBase(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: size * 1.1, height: size * 1.1)
                .blur(radius: 3)
                .offset(y: 2)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.82), Color(white: 0.35), Color(white: 0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.8)
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.24), Color(white: 0.08)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.42
                    )
                )
                .frame(width: size * 0.80, height: size * 0.80)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.95), Color(white: 0.55), Color(white: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.40, height: size * 0.40)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)

            Circle()
                .fill(Color(white: 0.12))
                .frame(width: size * 0.14, height: size * 0.14)
        }
        .frame(width: size, height: size)
    }

    private func armAssembly(width: CGFloat, height: CGFloat) -> some View {
        let pivotY = (width * 0.46) * 0.5
        let tubeWidth: CGFloat = max(3.5, width * 0.058)

        return ZStack(alignment: .top) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.75), Color(white: 0.25), Color(white: 0.65)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: tubeWidth * 2.6, height: height * 0.15)
                .offset(y: -height * 0.08)

            TonearmPath()
                .stroke(Color.black.opacity(0.35), lineWidth: tubeWidth * 1.5)
                .blur(radius: 2.5)
                .offset(x: 2, y: 3)

            TonearmPath()
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 0.98), Color(white: 0.55), Color(white: 0.92), Color(white: 0.40)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: tubeWidth, lineCap: .round, lineJoin: .round)
                )

            headshellAndCartridge(width: width, height: height)
        }
        .frame(width: width, height: height)
        .offset(y: pivotY)
    }

    private func headshellAndCartridge(width: CGFloat, height: CGFloat) -> some View {
        let headWidth = width * 0.24
        let headHeight = height * 0.22

        return ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.32), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: headWidth, height: headHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                }

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.85), Color(white: 0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2.5, height: headHeight * 0.45)
                .offset(x: headWidth * 0.52, y: -headHeight * 0.1)

            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.22, blue: 0.22), Color(red: 0.55, green: 0.08, blue: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: headWidth * 0.65, height: 4.5)

                Triangle()
                    .fill(Color(white: 0.95))
                    .frame(width: 3, height: 3.5)
                    .offset(y: 1)
            }
        }
        .frame(width: headWidth, height: headHeight)
        .rotationEffect(.degrees(24))
        .position(x: width * 0.31, y: height * 0.74)
    }
}

private struct TonearmPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startPoint = CGPoint(x: rect.width * 0.5, y: 0)
        let midPoint1 = CGPoint(x: rect.width * 0.58, y: rect.height * 0.28)
        let midPoint2 = CGPoint(x: rect.width * 0.42, y: rect.height * 0.55)
        let endPoint = CGPoint(x: rect.width * 0.31, y: rect.height * 0.74)

        path.move(to: startPoint)
        path.addCurve(
            to: midPoint1,
            control1: CGPoint(x: rect.width * 0.52, y: rect.height * 0.1),
            control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.2)
        )
        path.addCurve(
            to: midPoint2,
            control1: CGPoint(x: rect.width * 0.58, y: rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.45, y: rect.height * 0.48)
        )
        path.addCurve(
            to: endPoint,
            control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.62),
            control2: CGPoint(x: rect.width * 0.33, y: rect.height * 0.70)
        )
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
