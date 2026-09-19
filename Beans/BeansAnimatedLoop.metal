#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Dark diagonal bands with restrained cream, sage, rose, and violet light.
// The field is deliberately inexpensive because it runs during app launch.
[[ stitchable ]] half4 beansAnimatedBands(
    float2 position,
    half4 color,
    float4 boundingRect,
    float time,
    float bandWidth,
    float bandSpacing,
    float drift,
    float grain,
    half4 color1,
    half4 color2,
    half4 color3,
    half4 color4
) {
    (void)color;

    float2 size = boundingRect.zw;
    float2 uv = (position - size * 0.5) / max(min(size.x, size.y), 1.0);
    uv.y *= 0.92;

    float diagonal = uv.x * 0.86 + uv.y * 0.34;
    float moving = diagonal + time * drift * 0.018;
    float3 light = float3(0.008, 0.010, 0.012);
    float3 colors[4] = { float3(color1.rgb), float3(color2.rgb), float3(color3.rgb), float3(color4.rgb) };

    for (int index = 0; index < 4; index++) {
        float center = (float(index) - 1.5) * bandSpacing + sin(time * 0.11 + float(index) * 1.7) * 0.20;
        float distanceToBand = abs(fract(moving - center + 0.5) - 0.5);
        float beam = exp(-pow(distanceToBand / max(bandWidth, 0.001), 2.0));
        float glow = exp(-pow(distanceToBand / max(bandWidth * 3.2, 0.003), 2.0)) * 0.22;
        float variation = 0.76 + 0.24 * sin((uv.y + float(index) * 0.31) * 18.0 + time * 0.22);
        light += colors[index] * (beam * 0.86 + glow) * variation;
    }

    float vignette = 1.0 - smoothstep(0.42, 0.96, length(uv) * 0.88);
    float scan = 0.965 + 0.035 * sin(position.y * 0.72 + time * 0.35);
    float grainNoise = sin(dot(position, float2(0.013, 0.021)) + time * 0.12) * grain;
    light *= (0.68 + vignette * 0.46) * scan;
    light += grainNoise;
    return half4(half3(clamp(light, 0.0, 1.0)), 1.0);
}
