//
//  Shaders.metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn
{
    float4 pos [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct VertexOut {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
};

vertex VertexOut mapTexture(VertexIn input [[stage_in]]) {
    VertexOut outVertex;
    outVertex.renderedCoordinate = input.pos;
    outVertex.textureCoordinate = input.uv;
    return outVertex;
}

vertex VertexOut mapSphereTexture(VertexIn input [[stage_in]], constant float4x4& uniforms [[ buffer(2) ]]) {
    VertexOut outVertex;
    outVertex.renderedCoordinate = uniforms * input.pos;
    outVertex.textureCoordinate = input.uv;
    return outVertex;
}

fragment half4 displayTexture(VertexOut mappingVertex [[ stage_in ]],
                              texture2d<half, access::sample> texture [[ texture(0) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    return half4(texture.sample(s, mappingVertex.textureCoordinate));
}

fragment half4 displayYUVTexture(VertexOut in [[ stage_in ]],
                                  texture2d<half> yTexture [[ texture(0) ]],
                                  texture2d<half> uTexture [[ texture(1) ]],
                                  texture2d<half> vTexture [[ texture(2) ]],
                                  sampler textureSampler [[ sampler(0) ]],
                                  constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                  constant float3& colorOffset [[ buffer(1) ]],
                                  constant uchar3& leftShift [[ buffer(2) ]])
{
    half3 yuv;
    yuv.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
    return half4(half3x3(yuvToBGRMatrix)*(yuv*half3(leftShift)+half3(colorOffset)), 1);
}


fragment half4 displayNV12Texture(VertexOut in [[ stage_in ]],
                                  texture2d<half> lumaTexture [[ texture(0) ]],
                                  texture2d<half> chromaTexture [[ texture(1) ]],
                                  sampler textureSampler [[ sampler(0) ]],
                                  constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                  constant float3& colorOffset [[ buffer(1) ]],
                                  constant uchar3& leftShift [[ buffer(2) ]])
{
    half3 yuv;
    yuv.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.yz = chromaTexture.sample(textureSampler, in.textureCoordinate).rg;
    return half4(half3x3(yuvToBGRMatrix)*(yuv*half3(leftShift)+half3(colorOffset)), 1);
}

half3 shaderLinearize(half3 rgb) {
    rgb = pow(max(rgb,0), half3(4096.0/(2523 * 128)));
    rgb = max(rgb - half3(3424./4096), 0.0) / (half3(2413./4096 * 32) - half3(2392./4096 * 32) * rgb);
    rgb = pow(rgb, half3(4096.0 * 4 / 2610));
    return rgb;
}

half3 shaderDeLinearize(half3 rgb) {
    rgb = pow(max(rgb,0), half3(2610./4096 / 4));
    rgb = (half3(3424./4096) - half3(2413./4096 * 32) * rgb) / (half3(1.0) + half3(2392./4096 * 32) * rgb);
    rgb = pow(rgb, half3(2523./4096 * 128));
    return rgb;
}

// --- HDR→SDR tone-mapping (KSOptions.enableToneMapping) ---
// Fragments decode the source EOTF (PQ/HLG) to linear light, apply an
// ACES-style curve, and encode to sRGB so the output is display-referred SDR.

// BT.2100 HLG EOTF → relative linear light (1.0 ≈ reference peak).
half3 shaderHLGToLinear(half3 e) {
    e = max(e, 0.0);
    half3 under = e * e * half3(1.0 / 3.0);
    half3 over = (exp((e - half3(0.55991073)) * half3(1.0 / 0.17883277)) + half3(0.28466892)) * half3(1.0 / 12.0);
    return mix(under, over, step(half3(0.5), e));
}

// sRGB OETF (linear → sRGB-encoded).
half3 shaderLinearToSRGB(half3 l) {
    l = max(l, 0.0);
    half3 lo = half3(12.92) * l;
    half3 hi = half3(1.055) * pow(l, half3(1.0 / 2.4)) - half3(0.055);
    return mix(lo, hi, step(half3(0.0031308), l));
}

// ACES fitted approximation (Narkowicz). Linear-light in, SDR-referred out.
half3 shaderACESToneMap(half3 x) {
    const half a = 2.51;
    const half b = 0.03;
    const half c = 2.43;
    const half d = 0.59;
    const half e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// transferType: 1 = PQ (ST 2084), 2 = HLG (BT.2100). Anything else is a no-op.
half3 shaderToneMapRGB(half3 rgb, int transferType) {
    half3 linear;
    if (transferType == 2) {
        // HLG EOTF gives relative light where 0.5 ≈ SDR white (~0.0833); ×2
        // brings that into ACES mid-gray.
        linear = shaderHLGToLinear(rgb) * half3(2.0);
    } else {
        // shaderLinearize is the PQ EOTF (absolute nits/10000); ×20 maps
        // 100-nits white onto ACES mid-gray.
        linear = shaderLinearize(rgb) * half3(20.0);
    }
    return shaderLinearToSRGB(shaderACESToneMap(linear));
}

fragment half4 displayNV12TextureToneMapped(VertexOut in [[ stage_in ]],
                                            texture2d<half> lumaTexture [[ texture(0) ]],
                                            texture2d<half> chromaTexture [[ texture(1) ]],
                                            sampler textureSampler [[ sampler(0) ]],
                                            constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                            constant float3& colorOffset [[ buffer(1) ]],
                                            constant uchar3& leftShift [[ buffer(2) ]],
                                            constant int& transferType [[ buffer(3) ]])
{
    half3 yuv;
    yuv.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.yz = chromaTexture.sample(textureSampler, in.textureCoordinate).rg;
    half3 rgb = half3x3(yuvToBGRMatrix)*(yuv*half3(leftShift)+half3(colorOffset));
    return half4(shaderToneMapRGB(rgb, transferType), 1);
}

fragment half4 displayYUVTextureToneMapped(VertexOut in [[ stage_in ]],
                                           texture2d<half> yTexture [[ texture(0) ]],
                                           texture2d<half> uTexture [[ texture(1) ]],
                                           texture2d<half> vTexture [[ texture(2) ]],
                                           sampler textureSampler [[ sampler(0) ]],
                                           constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                           constant float3& colorOffset [[ buffer(1) ]],
                                           constant uchar3& leftShift [[ buffer(2) ]],
                                           constant int& transferType [[ buffer(3) ]])
{
    half3 yuv;
    yuv.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
    half3 rgb = half3x3(yuvToBGRMatrix)*(yuv*half3(leftShift)+half3(colorOffset));
    return half4(shaderToneMapRGB(rgb, transferType), 1);
}

fragment half4 displayYCCTexture(VertexOut in [[ stage_in ]],
                                  texture2d<half> lumaTexture [[ texture(0) ]],
                                  texture2d<half> chromaTexture [[ texture(1) ]],
                                  sampler textureSampler [[ sampler(0) ]],
                                  constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                  constant float3& colorOffset [[ buffer(1) ]],
                                  constant uchar3& leftShift [[ buffer(2) ]])
{
    half3 ipt;
    ipt.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
    ipt.yz = chromaTexture.sample(textureSampler, in.textureCoordinate).rg;
//    half3x3 ipt2lms = half3x3{{1, 0.1952, 0.4104}, {1, -0.2278, 0.2264}, {1, 0.0652, -1.3538}};
//    half3x3 lms2rgb = half3x3{{3.238998, -0.719461, -0.002862}, {-2.272734, 1.874998, -0.268066}, {0.086733, -0.158947, 1.074494}};
    half3x3 ipt2lms = half3x3{{1, 799/8192, 1681/8192}, {1, -933/8192, 1091/8192}, {1, 267/8192, -5545/8192}};
    half3x3 lms2rgb = half3x3{{3.43661, -0.79133, -0.0259499}, {-2.50645, 1.98360, -0.0989137}, {0.06984, -0.192271, 1.12486}};
    half3 lms = ipt2lms*ipt;
    lms = shaderLinearize(lms);
    half3 rgb = lms2rgb*lms;
    rgb = shaderDeLinearize(rgb);
    return half4(rgb, 1);
}
