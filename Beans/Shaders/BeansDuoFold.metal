// Adapted from DuoLikeAnimation by Elijah Semyonov under the MIT License.
// See THIRD_PARTY_NOTICES.md for the complete notice.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

constant int kBlurTaps = 32;
constant float kGoldenAngle = 2.39996322972865332;
constant float kTwoPi = 6.28318530717958648;

static float hash21(float2 point) {
    return fract(sin(dot(point, float2(12.9898, 78.233))) * 43758.5453);
}

static half4 opaque(half4 premultiplied) {
    return half4(premultiplied.rgb, 1.0h);
}

[[ stitchable ]] half4 beansDuoFold(float2 position,
                                    SwiftUI::Layer layer,
                                    float4 bounds,
                                    float angle,
                                    float eyeDistance,
                                    float blurSpread,
                                    float darkening) {
    const float2 size = bounds.zw;
    const float2 point = position - bounds.xy;
    const float tilt = abs(angle);
    if (tilt < 1e-5) {
        return opaque(layer.sample(position));
    }

    const bool hingeRight = angle > 0.0;
    const float hingeX = hingeRight ? size.x : 0.0;
    const float side = hingeRight ? -1.0 : 1.0;
    const float distance = abs(point.x - hingeX);
    const float3 glass = float3(hingeX + side * distance * cos(tilt), point.y, distance * sin(tilt));
    const float3 eye = float3(size * 0.5, eyeDistance);
    const float depth = eye.z - glass.z;
    if (depth <= 1e-3) {
        return half4(0.0h, 0.0h, 0.0h, 1.0h);
    }

    const float rayScale = eye.z / depth;
    const float2 hit = eye.xy + (glass.xy - eye.xy) * rayScale;
    const float radius = blurSpread * glass.z;
    if (any(hit < -radius) || any(hit > size + radius)) {
        return half4(0.0h, 0.0h, 0.0h, 1.0h);
    }

    const half attenuation = half(max(1.0 - darkening * radius, 0.0));
    if (radius < 0.5) {
        return opaque(layer.sample(bounds.xy + hit) * attenuation);
    }

    const int taps = clamp(int(radius * 2.0), 6, kBlurTaps);
    const float rotation = hash21(position) * kTwoPi;
    half3 sum = half3(0.0h);
    for (int index = 0; index < taps; ++index) {
        const float sampleRadius = radius * sqrt((float(index) + 0.5) / float(taps));
        const float sampleAngle = float(index) * kGoldenAngle + rotation;
        const float2 offset = sampleRadius * float2(cos(sampleAngle), sin(sampleAngle));
        sum += layer.sample(bounds.xy + hit + offset).rgb;
    }
    return half4(sum / half(taps) * attenuation, 1.0h);
}
