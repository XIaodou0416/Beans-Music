#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A compact ring-loop shader based on the same animated-distance approach as
// ShipSwift's AnimatedLoop. It intentionally keeps the launch variant small.
[[ stitchable ]] half4 beansAnimatedLoop(
    float2 position,
    half4 color,
    float4 boundingRect,
    float time,
    float speed,
    float lineWidth,
    float lines,
    float spacing,
    float channelOffset,
    float patternMod,
    float rotation,
    float scale,
    float2 center,
    float shape,
    float petals,
    half4 color1,
    half4 color2,
    half4 color3,
    half4 background
) {
    (void)color;
    (void)rotation;
    (void)shape;
    (void)petals;

    float2 size = boundingRect.zw;
    float2 uv = (position * 2.0 - size) / max(min(size.x, size.y), 1.0);
    uv = uv / max(scale, 0.0001) - center;

    float distanceFromCenter = length(uv);
    float phase = time * speed;
    float pattern = fmod(uv.x + uv.y, max(patternMod, 0.0001));
    int count = max(1, int(lines));
    float3 channels[3] = { float3(color1.rgb), float3(color2.rgb), float3(color3.rgb) };
    float3 outputColor = float3(background.rgb);

    for (int channel = 0; channel < 3; channel++) {
        float accumulation = 0.0;
        for (int ring = 0; ring < count; ring++) {
            float field = fract(phase - channelOffset * float(channel) + 0.012 * float(ring))
                * spacing - distanceFromCenter + pattern;
            accumulation += lineWidth * float((ring + 1) * (ring + 1))
                / max(abs(field), 0.00001);
        }
        outputColor += channels[channel] * accumulation;
    }

    return half4(half3(outputColor), 1.0);
}
