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

private struct BeansDuoParameters {
    let eyeDistancePoints: CGFloat = 1_920
    let blurSpread: CGFloat = 0.12
    let darkening: CGFloat = 0.015
}

@available(iOS 17.0, *)
private extension View {
    func beansDuoFoldEffect(angle: Double) -> some View {
        let parameters = BeansDuoParameters()
        return compositingGroup()
            .visualEffect { content, _ in
                content.layerEffect(
                    ShaderLibrary.beansDuoFold(
                        .boundingRect,
                        .float(angle),
                        .float(parameters.eyeDistancePoints),
                        .float(parameters.blurSpread),
                        .float(parameters.darkening)
                    ),
                    maxSampleOffset: .zero,
                    isEnabled: abs(angle) > 0.0001
                )
            }
    }
}

struct BeansDuoEffectModifier: ViewModifier {
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = BeansDuoMotionModel()

    func body(content: Content) -> some View {
        Group {
            if isEnabled && !reduceMotion {
                if #available(iOS 17.0, *) {
                    content.beansDuoFoldEffect(angle: motion.tiltAngle)
                } else {
                    content
                }
            } else {
                content
            }
        }
        .onAppear { updateMotion() }
        .onChange(of: isEnabled) { _ in updateMotion() }
        .onChange(of: reduceMotion) { _ in updateMotion() }
        .onDisappear { motion.stop() }
    }

    private func updateMotion() {
        guard isEnabled, !reduceMotion else {
            motion.stop()
            return
        }
        guard #available(iOS 17.0, *) else { return }
        motion.start()
    }
}
