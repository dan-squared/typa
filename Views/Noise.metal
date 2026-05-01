#include <metal_stdlib>
using namespace metal;

// Generates a pixel-perfect, infinite, non-repeating luma film grain.
[[ stitchable ]] half4 filmGrain(float2 position, half4 color) {
    float random = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    half n = half(random);
    return half4(n, n, n, 1.0h);
}
