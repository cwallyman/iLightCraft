//
//  Canvas.metal
//  Unveil
//

#include <metal_stdlib>
using namespace metal;

// The vertex shader draws the image as a four-vertex triangle strip with no vertex buffer.
// The quad's NDC corners arrive as one float4 (min.xy, max.xy) set with setVertexBytes.

// The fragment shader samples the frame with bilinear filtering and returns it unchanged:
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

fragment float4 canvasFragment(
    CanvasVertex      in    [[stage_in]],
    texture2d<float>  image [[texture(0)]]
) {
    // The rgba8Unorm texture reads the bytes raw and the bgra8Unorm drawable stores them raw
    // (Metal reorders the channels on store), so the swizzle is free.
    constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
    return image.sample(bilinear, in.textureCoordinate);
}
