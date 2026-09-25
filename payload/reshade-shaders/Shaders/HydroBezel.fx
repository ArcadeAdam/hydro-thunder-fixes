// Hydro Thunder bezel, composed at the final D3D11 output resolution.
// The original 1920x1080 PNG is loaded without resizing its texture.
// Scene UVs are unchanged: no game scaling, cropping, or new pillarboxing.
// Standalone ReShade FX; no shader packs or includes required.

texture2D HydroScene : COLOR;
sampler2D HydroSceneSampler
{
    Texture = HydroScene;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = POINT;
};

texture2D HydroArtwork < source = "bezel.png"; >
{
    Width = 1920;
    Height = 1080;
    Format = RGBA8;
};
sampler2D HydroArtworkSampler
{
    Texture = HydroArtwork;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = POINT;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

void HydroBezelVS(uint vertexID : SV_VertexID,
                  out float4 position : SV_Position,
                  out float2 uv : TEXCOORD)
{
    uv = float2((vertexID << 1) & 2, vertexID & 2);
    position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float4 HydroBezelPS(float4 position : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 scene = tex2D(HydroSceneSampler, uv);
    float4 artwork = tex2D(HydroArtworkSampler, uv);
    return float4(lerp(scene.rgb, artwork.rgb, artwork.a), scene.a);
}

technique HydroBezel < ui_label = "Hydro Thunder bezel"; >
{
    pass
    {
        VertexShader = HydroBezelVS;
        PixelShader = HydroBezelPS;
    }
}
