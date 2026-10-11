//
//  Canvas.metal
//  Unveil
//

#include <metal_stdlib>
using namespace metal;

// The vertex shader draws the image as a four-vertex triangle strip with no vertex buffer.
// The quad's NDC corners arrive as one float4 (min.xy, max.xy) set with setVertexBytes.

// The fragment shader samples the frame and returns it unchanged, apart from the pixel grid:
// the engine's pixels are already display-encoded sRGB, so no transfer function is needed.

struct CanvasVertex {
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex CanvasVertex canvasVertex(
    uint            vertexID [[vertex_id]],
    constant float4 &quad    [[buffer(0)]]
) {
    // Strip order: bottom-left, bottom-right, top-left, top-right.
    float2 corner = float2(float(vertexID & 1u), float(vertexID >> 1u));

    // Texture row 0 is the image's top row while NDC y points up, so the top samples v = 0.
    CanvasVertex out;
    out.position          = float4(mix(quad.xy, quad.zw, corner), 0.0, 1.0);
    out.textureCoordinate = float2(corner.x, 1.0 - corner.y);
    return out;
}

// CanvasStyle is how one quad is sampled (CanvasView.CanvasStyle): grid lines every image pixel
// of gridSize (none at gridOpacity 0); nearest 1 for real pixels from 99.8 %, else bilinear;
// clipping marks clipped pixels (ClippingOverlay: 1 shadows in blue, 2 highlights in red).
struct CanvasStyle {
    float2 gridSize;
    float  gridOpacity;
    uint   nearest;
    uint   clipping;
};

fragment float4 canvasFragment(
    CanvasVertex         in    [[stage_in]],
    texture2d<float>     image [[texture(0)]],
    constant CanvasStyle &style [[buffer(0)]]
) {
    // The rgba8Unorm texture reads the bytes raw and the bgra8Unorm drawable stores them raw
    // (Metal reorders the channels on store), so the swizzle is free.
    constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);

    float4 color = style.nearest != 0 ? image.sample(nearest, in.textureCoordinate)
                                      : image.sample(bilinear, in.textureCoordinate);

    // Distance to the nearest image pixel boundary, in screen pixels (fwidth is the change
    // of image pixels per screen pixel): a line one screen pixel wide, whatever the zoom.
    float2 pixel    = in.textureCoordinate * style.gridSize;
    float2 distance = abs(fract(pixel + 0.5) - 0.5) / max(fwidth(pixel), 1e-6);
    float  line     = 1.0 - saturate(min(distance.x, distance.y));

    // Neutral: a step toward mid grey, visible on light and dark pixels alike.
    color.rgb = mix(color.rgb, float3(0.5), line * style.gridOpacity);

    // Clipping is a property of one pixel: test the nearest texel, never a bilinear blend of several.
    if (style.clipping != 0u) {
        float3 texel = image.sample(nearest, in.textureCoordinate).rgb;
        if ((style.clipping & 2u) != 0u && any(texel > 254.5 / 255.0)) {
            color.rgb = float3(1.0, 0.0, 0.0);
        } else if ((style.clipping & 1u) != 0u && any(texel < 0.5 / 255.0)) {
            color.rgb = float3(0.0, 0.0, 1.0);
        }
    }
    return color;
}
