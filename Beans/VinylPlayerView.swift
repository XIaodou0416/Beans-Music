import SwiftUI

import UIKit



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

/// Interactive release-style vinyl stage: continuous rotation, tonearm state,
/// tap-to-open lyrics, and horizontal swipe-to-switch tracks.
struct VinylTurntableView: View {
    let coverURL: URL?
    let isPlaying: Bool
    let trackId: Int?
    let size: CGFloat
    var onTap: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    @State private var rotationState = RecordRotationState()
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isTransitioningTrack = false

    init(coverURL: URL?, isPlaying: Bool, trackId: Int? = nil, size: CGFloat = 280, onTap: (() -> Void)? = nil, onNextTrack: (() -> Void)? = nil, onPreviousTrack: (() -> Void)? = nil) {
        self.coverURL = coverURL
        self.isPlaying = isPlaying
        self.trackId = trackId
        self.size = size
        self.onTap = onTap
        self.onNextTrack = onNextTrack
        self.onPreviousTrack = onPreviousTrack
    }

    var body: some View {
        let armHeight = size * 0.68

        ZStack(alignment: .top) {
            TimelineView(.animation(paused: !isPlaying || isDragging || isTransitioningTrack)) { timeline in
                VinylRecordView(coverURL: coverURL, size: size)
                    .rotationEffect(.degrees(rotationState.currentAngle(at: timeline.date)))
            }
            .offset(x: dragOffset)
            .padding(.top, armHeight * 0.36)
            .contentShape(Circle())
            .gesture(swipeGesture)
            .onTapGesture { onTap?() }
            .zIndex(1)

            VinylTonearmView(isPlaying: isPlaying && !isDragging && !isTransitioningTrack, height: armHeight, reduceMotion: UIAccessibility.isReduceMotionEnabled)
                .offset(x: size * 0.12, y: -armHeight * 0.08)
                .allowsHitTesting(false)
                .zIndex(2)
        }
        .frame(width: size + 48, height: size + armHeight * 0.38, alignment: .top)
        .onAppear {
            if isPlaying { rotationState.start() }
        }
        .onChange(of: isPlaying) { playing in
            if playing { rotationState.start() } else { rotationState.stop() }
        }
        .onChange(of: trackId) { _ in
            isTransitioningTrack = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                isTransitioningTrack = false
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let threshold: CGFloat = 45

                if translation < -threshold || predicted < -100 {
                    switchTrack(offset: -size * 1.25, callback: onNextTrack)
                } else if translation > threshold || predicted > 100 {
                    switchTrack(offset: size * 1.25, callback: onPreviousTrack)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
            }
    }

    private func switchTrack(offset: CGFloat, callback: (() -> Void)?) {
        withAnimation(.easeOut(duration: 0.20)) { dragOffset = offset }
        callback?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            dragOffset = offset > 0 ? -size * 1.25 : size * 1.25
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                dragOffset = 0
                isDragging = false
            }
        }
    }
}

/// A programmatic vinyl record so the player does not need another image asset.
struct VinylRecordView: View {
    let coverURL: URL?
    let size: CGFloat

    init(coverURL: URL?, size: CGFloat = 280) {
        self.coverURL = coverURL
        self.size = size
    }

    var body: some View {
        let labelSize = size * 0.64
        let spindleSize = max(7, size * 0.032)

        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: max(8, size * 0.045))
                .offset(y: size * 0.04)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.16), Color(white: 0.08), Color(white: 0.025)],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.52
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Circle().stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.04), .black.opacity(0.6)],
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
                            .white.opacity(0.04), .white.opacity(0.16), .black.opacity(0.16),
                            .white.opacity(0.11), .black.opacity(0.12), .white.opacity(0.05)
                        ]),
                        center: .center
                    )
                )
                .frame(width: size - 4, height: size - 4)
                .opacity(0.9)

            ForEach(0..<18, id: \.self) { index in
                let factor = 0.68 + (Double(index) / 17) * 0.29
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(index % 4 == 0 ? 0.14 : 0.06), .black.opacity(0.42), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: index % 4 == 0 ? 0.8 : 0.45
                    )
                    .frame(width: size * factor, height: size * factor)
            }

            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white.opacity(0.22), location: 0.15),
                            .init(color: .clear, location: 0.28),
                            .init(color: .clear, location: 0.52),
                            .init(color: .white.opacity(0.14), location: 0.66),
                            .init(color: .clear, location: 0.82),
                            .init(color: .clear, location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(35)
                    )
                )
                .frame(width: size - 2, height: size - 2)
                .blendMode(.screen)
                .allowsHitTesting(false)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: labelSize + 6, height: labelSize + 6)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)

                Group {
                    if coverURL != nil {
                        CoverImage(url: coverURL, size: labelSize, cornerRadius: labelSize / 2)
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "music.note")
                                .font(.system(size: labelSize * 0.35, weight: .light))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(width: labelSize, height: labelSize)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1.5) }

                Circle()
                    .stroke(.white.opacity(0.26), lineWidth: 0.8)
                    .frame(width: labelSize * 0.86, height: labelSize * 0.86)

                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.45), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: spindleSize * 2.4, height: spindleSize * 2.4)
                Circle()
                    .fill(Color(white: 0.04))
                    .frame(width: spindleSize, height: spindleSize)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}

/// A small vector tonearm that lifts while paused and settles onto the record
/// while playing. It uses no platform-specific drawing APIs.
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
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.28), Color(white: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: pivotSize, height: pivotSize)
                .overlay {
                    Circle()
                        .fill(Color(white: 0.12))
                        .padding(pivotSize * 0.19)
                }
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                .zIndex(2)

            TonearmPath()
                .stroke(Color.black.opacity(0.36), lineWidth: max(5, width * 0.09))
                .blur(radius: 2)
                .offset(x: 2, y: 3)

            TonearmPath()
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.96), .white.opacity(0.52), .white.opacity(0.90), .white.opacity(0.38)], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: max(3.5, width * 0.058), lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(isPlaying ? 0 : -32), anchor: UnitPoint(x: 0.5, y: pivotSize * 0.5 / height))
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.74), value: isPlaying)
                .zIndex(1)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

private struct TonearmPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.width * 0.5, y: 0)
        let first = CGPoint(x: rect.width * 0.58, y: rect.height * 0.28)
        let second = CGPoint(x: rect.width * 0.42, y: rect.height * 0.55)
        let end = CGPoint(x: rect.width * 0.31, y: rect.height * 0.74)
        path.move(to: start)
        path.addCurve(to: first, control1: CGPoint(x: rect.width * 0.52, y: rect.height * 0.1), control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.2))
        path.addCurve(to: second, control1: CGPoint(x: rect.width * 0.58, y: rect.height * 0.38), control2: CGPoint(x: rect.width * 0.45, y: rect.height * 0.48))
        path.addCurve(to: end, control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.62), control2: CGPoint(x: rect.width * 0.33, y: rect.height * 0.70))
        return path
    }
}
