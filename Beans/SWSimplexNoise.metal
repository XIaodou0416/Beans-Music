//
//  SWSimplexNoise.metal
//  ShipSwift
//
//  Simplex-noise procedural background as a SwiftUI Metal `colorEffect`.
//
//  Algorithm: two layered 2D simplex noises composed into a 0..1 shape
//  value, then mapped across up to 10 base colors with `stepsPerColor`
//  banded transitions, `softness`-controlled smoothing, and `fwidth()`
//  derivative-based anti-aliasing. The first and last colors wrap
//  smoothly on either side of the gradient so the palette tiles.
//

#include <metal_stdlib>
using namespace metal;

namespace SWSimplexNoiseImpl {
    inline float2 mod289_2(float2 x) {
        return x - floor(x * (1.0 / 289.0)) * 289.0;
    }
    inline float3 mod289_3(float3 x) {
        return x - floor(x * (1.0 / 289.0)) * 289.0;
    }
    inline float3 permute289(float3 x) {
        return mod289_3((x * 34.0 + 1.0) * x);
    }

    // 2D simplex noise (Ashima Arts, public domain).
    inline float snoise(float2 v) {
        const float4 C = float4( 0.211324865405187,
                                  0.366025403784439,
                                 -0.577350269189626,
                                  0.024390243902439);
        float2 i  = floor(v + dot(v, C.yy));
        float2 x0 = v - i + dot(i, C.xx);
        float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
        float4 x12 = x0.xyxy + C.xxzz;
        x12.xy -= i1;
        i = mod289_2(i);
        float3 p = permute289(permute289(i.y + float3(0.0, i1.y, 1.0))
                              + i.x + float3(0.0, i1.x, 1.0));
        float3 m = max(0.5 - float3(dot(x0, x0),
                                     dot(x12.xy, x12.xy),
                                     dot(x12.zw, x12.zw)), 0.0);
        m = m * m;
        m = m * m;
        float3 x  = 2.0 * fract(p * C.www) - 1.0;
        float3 h  = abs(x) - 0.5;
        float3 ox = floor(x + 0.5);
        float3 a0 = x - ox;
        m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
        float3 g;
        g.x  = a0.x  * x0.x  + h.x  * x0.y;
        g.yz = a0.yz * x12.xz + h.yz * x12.yw;
        return 130.0 * dot(m, g);
    }

    inline half4 pickColor(int i,
                           half4 c0, half4 c1, half4 c2, half4 c3, half4 c4,
                           half4 c5, half4 c6, half4 c7, half4 c8, half4 c9) {
        switch (i) {
            case 0: return c0;
            case 1: return c1;
            case 2: return c2;
            case 3: return c3;
            case 4: return c4;
            case 5: return c5;
            case 6: return c6;
            case 7: return c7;
            case 8: return c8;
            default: return c9;
        }
    }

    inline float steppedSmooth(float m, float steps, float softness) {
        float stepT  = floor(m * steps) / steps;
        float f      = m * steps - floor(m * steps);
        float fw     = steps * fwidth(m);
        float smoothed = smoothstep(0.5 - softness,
                                    min(1.0, 0.5 + softness + fw),
                                    f);
        return stepT + smoothed / steps;
    }
}

// Procedural Simplex-Noise color background.
//
// Parameters:
//   - position       : pixel position (`SwiftUI::Layer`-relative).
//   - currentColor   : source color from `.colorEffect` (unused).
//   - boundingRect   : `(x, y, w, h)` of the view's bounding rect.
//   - time           : seconds since the renderer started.
//   - scale          : pattern zoom (higher = more cycles per pixel).
//   - colorsCount    : number of active palette entries, 1...10.
//   - stepsPerColor  : extra banded transitions per color pair, 1...10.
//   - softness       : smoothness of band-to-band transitions, 0...1.
//   - c0...c9        : up to 10 palette colors (SwiftUI `Color`s).
[[ stitchable ]] half4 swSimplexNoise(
    float2 position,
    half4  currentColor,
    float4 boundingRect,
    float  time,
    float  scale,
    float  colorsCount,
    float  stepsPerColor,
    float  softness,
    half4  c0, half4 c1, half4 c2, half4 c3, half4 c4,
    half4  c5, half4 c6, half4 c7, half4 c8, half4 c9
) {
    using namespace SWSimplexNoiseImpl;

    float2 size   = boundingRect.zw;
    float  minDim = max(min(size.x, size.y), 1.0);

    // Normalize so the shader is resolution-independent.
    float2 uv = (position - 0.5 * size) / minDim;
    uv /= max(scale, 0.001);
    uv *= 0.1; // `shape_uv *= .1`.

    float t = 0.2 * time;

    float noise  = 0.5 * snoise(uv - float2(0.0, 0.30 * t));
    noise       += 0.5 * snoise(2.0 * uv + float2(0.0, 0.32 * t));

    float shape = 0.5 + 0.5 * noise;

    float n     = max(1.0, colorsCount);
    float mixer = (shape - 0.5 / n) * n;
    float steps = max(1.0, stepsPerColor);

    half4 gradient = c0;
    gradient.rgb *= gradient.a;

    for (int i = 1; i < 10; i++) {
        if (i >= int(n)) break;
        float localM = clamp(mixer - float(i - 1), 0.0, 1.0);
        localM = steppedSmooth(localM, steps, 0.5 * softness);
        half4 cc = pickColor(i, c0, c1, c2, c3, c4, c5, c6, c7, c8, c9);
        cc.rgb *= cc.a;
        gradient = mix(gradient, cc, half(localM));
    }

    // Wrap zone — lets the first and last colors blend smoothly across
    // the gradient seam.
    if (mixer < 0.0 || mixer > (n - 1.0)) {
        float localM = (mixer < 0.0) ? (mixer + 1.0) : (mixer - (n - 1.0));
        localM = steppedSmooth(localM, steps, 0.5 * softness);
        half4 cFirst = c0;
        cFirst.rgb *= cFirst.a;
        half4 cLast = pickColor(int(n - 1.0),
                                c0, c1, c2, c3, c4, c5, c6, c7, c8, c9);
        cLast.rgb *= cLast.a;
        gradient = mix(cLast, cFirst, half(localM));
    }

    // Sub-pixel dither against gradient banding.
    float dither = fract(sin(dot(0.014 * position,
                                  float2(12.9898, 78.233))) * 43758.5453123) - 0.5;
    gradient.rgb += half3(half(dither / 256.0));

    return gradient;
}
