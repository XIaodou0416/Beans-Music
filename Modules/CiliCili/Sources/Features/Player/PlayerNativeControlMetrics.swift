import SwiftUI

struct PlayerNativeControlMetrics: Equatable {
    let controlHeight: CGFloat
    let progressControlHeight: CGFloat
    let sliderVisualScale: CGFloat
    let iconSize: CGFloat
    let timeFont: Font
    let stackSpacing: CGFloat
    let groupSpacing: CGFloat
    let controlSpacing: CGFloat
    let sliderHorizontalPadding: CGFloat
    let timeLabelWidth: CGFloat
    let qualityButtonMaxWidth: CGFloat
    let qualityHorizontalPadding: CGFloat

    var iconOnlyControlSize: CGFloat {
        controlHeight * 0.68
    }

    static let portrait = PlayerNativeControlMetrics(
        controlHeight: 28,
        progressControlHeight: 22,
        sliderVisualScale: 0.82,
        iconSize: 12,
        timeFont: .caption2.monospacedDigit(),
        stackSpacing: 5,
        groupSpacing: 5,
        controlSpacing: 4,
        sliderHorizontalPadding: 8,
        timeLabelWidth: 104,
        qualityButtonMaxWidth: 68,
        qualityHorizontalPadding: 6
    )

    static let livePortrait = PlayerNativeControlMetrics(
        controlHeight: 36,
        progressControlHeight: 26,
        sliderVisualScale: 0.90,
        iconSize: 15,
        timeFont: .caption.monospacedDigit(),
        stackSpacing: 7,
        groupSpacing: 7,
        controlSpacing: 7,
        sliderHorizontalPadding: 10,
        timeLabelWidth: 104,
        qualityButtonMaxWidth: 68,
        qualityHorizontalPadding: 8
    )

    static let landscape = PlayerNativeControlMetrics(
        controlHeight: 34,
        progressControlHeight: 26,
        sliderVisualScale: 0.92,
        iconSize: 14,
        timeFont: .caption.monospacedDigit(),
        stackSpacing: 7,
        groupSpacing: 7,
        controlSpacing: 6,
        sliderHorizontalPadding: 11,
        timeLabelWidth: 86,
        qualityButtonMaxWidth: 92,
        qualityHorizontalPadding: 9
    )

    func sized(controlHeight: CGFloat, iconSize: CGFloat) -> PlayerNativeControlMetrics {
        PlayerNativeControlMetrics(
            controlHeight: controlHeight,
            progressControlHeight: progressControlHeight,
            sliderVisualScale: sliderVisualScale,
            iconSize: iconSize,
            timeFont: timeFont,
            stackSpacing: stackSpacing,
            groupSpacing: groupSpacing,
            controlSpacing: controlSpacing,
            sliderHorizontalPadding: sliderHorizontalPadding,
            timeLabelWidth: timeLabelWidth,
            qualityButtonMaxWidth: qualityButtonMaxWidth,
            qualityHorizontalPadding: qualityHorizontalPadding
        )
    }
}

private struct PlayerNativeControlMetricsKey: EnvironmentKey {
    static let defaultValue = PlayerNativeControlMetrics.portrait
}

extension EnvironmentValues {
    var playerNativeControlMetrics: PlayerNativeControlMetrics {
        get { self[PlayerNativeControlMetricsKey.self] }
        set { self[PlayerNativeControlMetricsKey.self] = newValue }
    }
}
