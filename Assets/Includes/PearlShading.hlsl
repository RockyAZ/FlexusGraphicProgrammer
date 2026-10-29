#ifndef PEARL_SHADING
#define PEARL_SHADING

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

float4 ShadePearl(
float3 albedo,
float metallic,
float smoothness,
float3 N,
float3 V,
float4 shadowCoord,
float3 positionWS,
float3 pearlColorCenter,
float3 pearlColorEdge,
float pearlSpread,
float mixingPearlSpecular,
float mixingPearlNormalPow,
float mixingShadowValue)
{
    Light mainLight = GetMainLight(shadowCoord);
    float3 L = mainLight.direction;
    float attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    float3 lightColor = mainLight.color * attenuation;
    N = normalize(N);
    L = normalize(L);
    float3 H = normalize(L + V); //floatvector for specular calculations, cheaper than R = 2 * dot(N, L) * N - L

    //pearl calculation
    float NdotV = saturate(dot(N, V));
    float pearlFactor = pow(1.0 - NdotV, pearlSpread);
    float3 resultPearlColor = lerp(pearlColorCenter, pearlColorEdge, pearlFactor);

    float3 dielectricSpec = float3(0.04, 0.04, 0.04); // Non-metals reflect ~4 % of light
    float3 baseSpecular = lerp(dielectricSpec, albedo, metallic);

    float3 specularColor = lerp(baseSpecular, resultPearlColor, mixingPearlSpecular);

    float NdotL = dot(N, L);
    float NdotLSaturate = saturate(NdotL);

    //diffuse
    float3 diffuseColor = albedo * (1.0 - metallic);
    float mixingPearl = pow(NdotV, mixingPearlNormalPow);
    diffuseColor = lerp(diffuseColor, resultPearlColor, mixingPearl);

    float diffuseMultiplier = saturate(NdotL + mixingShadowValue);
    float3 directDiffuse = diffuseColor * diffuseMultiplier;
    float3 indirectDiffuse = SampleSH(N) * diffuseColor;

    float NdotH = saturate(dot(N, H));

    float3 viewReflect = reflect( -V, N);
    float perceptualRoughness = 1.0 - smoothness;

    //baked cubemap reflections
    float3 envReflection = GlossyEnvironmentReflection(viewReflect, positionWS, perceptualRoughness, 1.0);
    float3 indirectSpecular = envReflection * specularColor;

    float specPower = exp2(10.0 * smoothness + 1.0);

    float3 directSpecular = specularColor * pow(NdotH, specPower) * smoothness;

    float3 finalColor = (directDiffuse + directSpecular) * lightColor + indirectDiffuse + indirectSpecular;
    return float4(finalColor, 1.0);
}


//NOISE
// Smooth 3D Gradient Hash (returns a normalized direction vector)
float3 hash3D(float3 p)
{
    p = float3(
    dot(p, float3(127.1, 311.7, 74.7)),
    dot(p, float3(269.5, 183.3, 246.1)),
    dot(p, float3(113.5, 271.9, 124.6))
    );
    return - 1.0 + 2.0 * frac(sin(p) * 43758.5453123);
}

// 3D Gradient (Perlin) Noise for organic, artifact-free waves
float noise3D(float3 x)
{
    float3 i = floor(x);
    float3 f = frac(x);

    // Quintic interpolant for much smoother transitions
    // (This strictly eliminates the linear "dashes" and blocky grid artifacts of value noise)
    float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Calculate gradient dot products at the 8 corners of the 3D cell
    float n000 = dot(hash3D(i + float3(0, 0, 0)), f - float3(0, 0, 0));
    float n100 = dot(hash3D(i + float3(1, 0, 0)), f - float3(1, 0, 0));
    float n010 = dot(hash3D(i + float3(0, 1, 0)), f - float3(0, 1, 0));
    float n110 = dot(hash3D(i + float3(1, 1, 0)), f - float3(1, 1, 0));
    float n001 = dot(hash3D(i + float3(0, 0, 1)), f - float3(0, 0, 1));
    float n101 = dot(hash3D(i + float3(1, 0, 1)), f - float3(1, 0, 1));
    float n011 = dot(hash3D(i + float3(0, 1, 1)), f - float3(0, 1, 1));
    float n111 = dot(hash3D(i + float3(1, 1, 1)), f - float3(1, 1, 1));

    // Trilinear interpolation of the gradients
    float noiseValue = lerp(
    lerp(lerp(n000, n100, u.x), lerp(n010, n110, u.x), u.y),
    lerp(lerp(n001, n101, u.x), lerp(n011, n111, u.x), u.y), u.z);

    // [-1, 1]
    return noiseValue;
}

float GetNoiseHeight(float3 position, float time, float scale, float speed, float amount)
{ //getting rid of the movement illusion
    float3 noiseSamplePos = position * scale + float3(0, time * speed, 0);
    float noiseValue = noise3D(noiseSamplePos);
    return noiseValue * amount;
}

#endif
