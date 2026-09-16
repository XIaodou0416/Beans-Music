//
//  BeansDuoEffect.swift
//
//  Adapted from DuoLikeAnimation by Elijah Semyonov under the MIT License.
//  See THIRD_PARTY_NOTICES.md for the complete notice.
//

import CoreMotion
import SwiftUI
import UIKit
import simd

@MainActor
final class BeansDuoMotionModel: ObservableObject {
    @Published private(set) var tiltAngle: Double = 0

    private let motionManager = CMMotionManager()
    private var reference: simd_double3x3?
    private var rowsAreDeviceAxes: Bool?
    private let smoothing = 0.7
    private let predictionInterval = 0.04

    func start() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 120.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor [weak self] in
                self?.process(motion)
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        reference = nil
        rowsAreDeviceAxes = nil
        tiltAngle = 0
    }

    private func process(_ motion: CMDeviceMotion) {
        let deviceToReference = deviceToReferenceMatrix(motion)
        guard let reference else {
            self.reference = deviceToReference
            return
        }

        let relative = reference.transpose * deviceToReference
        let normal = relative.columns.2
        let axes = screenAxesInDeviceSpace()
        let measured = atan2(simd_dot(normal, axes.x), normal.z)
        let rate = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
        let predicted = measured + simd_dot(rate, axes.y) * predictionInterval
        tiltAngle += (predicted - tiltAngle) * smoothing
    }

    private func deviceToReferenceMatrix(_ motion: CMDeviceMotion) -> simd_double3x3 {
        let matrix = motion.attitude.rotationMatrix
        let asRows = simd_double3x3(rows: [
            SIMD3(matrix.m11, matrix.m12, matrix.m13),
            SIMD3(matrix.m21, matrix.m22, matrix.m23),
            SIMD3(matrix.m31, matrix.m32, matrix.m33)
        ])

        if rowsAreDeviceAxes == nil {
            let gravity = simd_normalize(SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z))
            let down = SIMD3(0.0, 0.0, -1.0)
            let rowsScore = simd_dot(gravity, asRows * down)
            let columnsScore = simd_dot(gravity, asRows.transpose * down)
            if abs(rowsScore - columnsScore) > 0.2 {
                rowsAreDeviceAxes = rowsScore > columnsScore
            }
        }
        return (rowsAreDeviceAxes ?? true) ? asRows.transpose : asRows
    }

    private func screenAxesInDeviceSpace() -> (x: SIMD3<Double>, y: SIMD3<Double>) {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft: return (SIMD3(0, 1, 0), SIMD3(-1, 0, 0))
        case .landscapeRight: return (SIMD3(0, -1, 0), SIMD3(1, 0, 0))
        case .portraitUpsideDown: return (SIMD3(-1, 0, 0), SIMD3(0, -1, 0))
        default: return (SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        }
    }
}

private struct BeansDuoGlassOverlay: View {
    let angle: Double

    private var strength: Double {
        min(1, abs(angle) / 0.48)
    }

    private var hingeAtTrailingEdge: Bool {
        angle > 0
    }

    var body: some View {
        let start = hingeAtTrailingEdge ? UnitPoint.trailing : .leading
        let end = hingeAtTrailingEdge ? UnitPoint.leading : .trailing
        ZStack {
            LinearGradient(
                colors: [.clear, .black.opacity(0.25 * strength)],
                startPoint: start,
                endPoint: end
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.62 * strength)
                .mask {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: start,
                        endPoint: end
                    )
                }
        }
    }
}

private struct BeansDuoSystemChrome: View {
    @Environment(\.colorScheme) private var colorScheme

    private var chromeColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { timeline in
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Text(timeline.date, format: .dateTime.hour().minute())
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100percent")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chromeColor)
                    .padding(.horizontal, 24)
                    .padding(.top, max(proxy.safeAreaInsets.top + 4, 14))

                    Spacer(minLength: 0)

                    Capsule()
                        .fill(chromeColor)
                        .frame(width: 132, height: 5)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 8, 14))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BeansDuoEffectModifier: ViewModifier {
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = BeansDuoMotionModel()

    private var clampedAngle: Double {
        min(0.48, max(-0.48, motion.tiltAngle))
    }

    private var rotationAnchor: UnitPoint {
        clampedAngle > 0 ? .trailing : .leading
    }

    func body(content: Content) -> some View {
        let transformedContent = Group {
            if isEnabled && !reduceMotion {
                content
                    .overlay {
                        BeansDuoSystemChrome()
                    }
                    .background(Color.black)
                    .rotation3DEffect(
                        .radians(clampedAngle),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: rotationAnchor,
                        perspective: 0.72
                    )
                    .overlay {
                        BeansDuoGlassOverlay(angle: clampedAngle)
                            .allowsHitTesting(false)
                    }
                    .clipped()
            } else {
                content
            }
        }
        .statusBar(hidden: isEnabled && !reduceMotion)

        if #available(iOS 16.0, *) {
            transformedContent
                .persistentSystemOverlays(isEnabled && !reduceMotion ? .hidden : .visible)
                .onAppear { updateMotion() }
                .onChange(of: isEnabled) { _ in updateMotion() }
                .onChange(of: reduceMotion) { _ in updateMotion() }
                .onDisappear { motion.stop() }
        } else {
            transformedContent
                .onAppear { updateMotion() }
                .onChange(of: isEnabled) { _ in updateMotion() }
                .onChange(of: reduceMotion) { _ in updateMotion() }
                .onDisappear { motion.stop() }
        }
    }

    private func updateMotion() {
        guard isEnabled, !reduceMotion else {
            motion.stop()
            return
        }
        motion.start()
    }
}
