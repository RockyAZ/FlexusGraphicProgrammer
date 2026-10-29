Shader "Flexus/TextureVertexDisplacementWithNoise_05"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _MetallicStrength("Metallic Strength", Range(0, 1)) = 0
        _Smoothness("Smoothness", Range(0.002, 1)) = 0.5
        [Header(Hameleon Pearl Settings)]
        _PearlColorCenter("Pearl Color (Facing)", Color) = (0.2, 0.8, 0.4, 1)
        _PearlColorEdge("Pearl Color (Angle)", Color) = (0.8, 0.2, 0.6, 1)
        _PearlSpread("Hameleon Spread", Range(0.1, 5.0)) = 1.5
        _MixingPearlSpecular("Mixing Pearl Specular", Range(0, 1.0)) = 1
        _MixingPearlNormalPow("Mixing Pearl Diffuse Normal Pow", Range(0.001, 25.0)) = 1
        [Header(Shadow)]
        _MixingShadowValue("Mixing Shadow", Range(0, 1.0)) = 1
        [Header(Texture displacement)]
        _DisplacementMap ("Displacement Map (Render Texture)", 2D) = "black" {}
        _DisplacementStrength ("Displacement Map Strength", Float) = 1.0
        _DisplacementMax ("Max value of displacement", Float) = 10.0
        [Header(Noise)]
        _NoiseScale ("Noise Scale", Float) = 5.0
        _NoiseSpeed ("Noise Speed", Float) = 2.0
        _NoiseAmount ("Noise displacement Amount", Float) = 0.5
        _OffsetTangents ("Offset Tangent Bitangent", Range(0.00001, 15)) = 0.001
        [Header(Activation layer)]
        _ActivationLayerColor("Activation Layer Color", Color) = (0, 0, 0, 1)
        _ActivationLayerSmoothness("Activation Layer Smoothness", Range(0.002, 1)) = 0.1
        _ActivationTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }
        LOD 100

        HLSLINCLUDE // Shared block for ForwardLit and ShadowCaster
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
        #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
        #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
        #include "./Includes/PearlShading.hlsl"

        TEXTURE2D_FLOAT(_DisplacementMap);
        SAMPLER(sampler_DisplacementMap);
        TEXTURE2D(_ActivationTex);
        SAMPLER(sampler_ActivationTex);

        CBUFFER_START(UnityPerMaterial)
        float4 _DisplacementMap_TexelSize;
        float4 _BaseColor;
        float _MetallicStrength;
        float _Smoothness;
        float4 _PearlColorCenter;
        float4 _PearlColorEdge;
        float _PearlSpread;
        float _MixingPearlSpecular;
        float _MixingPearlNormalPow;
        float _MixingShadowValue;
        float _DisplacementStrength;
        float _DisplacementMax;
        float _NoiseScale;
        float _NoiseSpeed;
        float _NoiseAmount;
        float _OffsetTangents;
        float4 _ActivationLayerColor;
        float _ActivationLayerSmoothness;
        CBUFFER_END

        float convert_to_minusone_one(float value)
        {
            return value * 2.0;
        }

        float3 GetDisplacedPositionWS(float3 positionWS, float3 normalWS, float2 uv)
        {
            float rawHeight = SAMPLE_TEXTURE2D_LOD(_DisplacementMap, sampler_DisplacementMap, uv, 0).r;
            float h0 = convert_to_minusone_one(rawHeight) * _DisplacementStrength;
            return positionWS + (normalWS * h0);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1; // Pre-noise WS pos (for noise gradient sampling)
                float3 finalPosWS : TEXCOORD2; // Exact rasterized WS pos (for shadow receiving)
                float3 normalWS : TEXCOORD3;
                float3 tangentWS : TEXCOORD4;
                float3 bitangentWS : TEXCOORD5;
                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                float4 screenPos : TEXCOORD6;
                #endif
            };

            Varyings vert(Attributes v)
            {
                Varyings o;

                float3 basePosWS = TransformObjectToWorld(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                float3 texDisplacedPosWS = GetDisplacedPositionWS(basePosWS, normalInput.normalWS, v.uv);

                float h0_noise = GetNoiseHeight(texDisplacedPosWS, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float3 finalPosWS = texDisplacedPosWS + normalInput.normalWS * h0_noise;

                o.positionWS = texDisplacedPosWS; // Pre-noise WS pos so frag noise matches vert noise
                o.finalPosWS = finalPosWS; // Linearly interpolated to match rasterized triangles 1 : 1
                o.positionCS = TransformWorldToHClip(finalPosWS);
                o.uv = v.uv;

                o.normalWS = normalInput.normalWS;
                o.tangentWS = normalInput.tangentWS;
                o.bitangentWS = normalInput.bitangentWS;

                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                o.screenPos = ComputeScreenPos(o.positionCS);
                #endif

                return o;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS);
                float3 bitangentWS = normalize(input.bitangentWS);

                // Noise gradients
                float3 p0 = input.positionWS;
                float3 p1 = p0 + tangentWS * _OffsetTangents;
                float3 p2 = p0 + bitangentWS * _OffsetTangents;

                float h0_noise = GetNoiseHeight(p0, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h1_noise = GetNoiseHeight(p1, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h2_noise = GetNoiseHeight(p2, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);

                float dNoise_dU = (h1_noise - h0_noise) / _OffsetTangents;
                float dNoise_dV = (h2_noise - h0_noise) / _OffsetTangents;

                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.finalPosWS);

                // Central difference over a 1.5-texel radius
                float2 stepUV = _DisplacementMap_TexelSize.xy * 1.5;
                float pixelActivation = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv).b;

                float rawH_Right = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv + float2(stepUV.x, 0)).r;
                float rawH_Left = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv - float2(stepUV.x, 0)).r;
                float rawH_Up = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv + float2(0, stepUV.y)).r;
                float rawH_Down = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv - float2(0, stepUV.y)).r;

                float hRight = convert_to_minusone_one(rawH_Right) * _DisplacementStrength;
                float hLeft = convert_to_minusone_one(rawH_Left) * _DisplacementStrength;
                float hUp = convert_to_minusone_one(rawH_Up) * _DisplacementStrength;
                float hDown = convert_to_minusone_one(rawH_Down) * _DisplacementStrength;

                float dTex_dU = (hRight - hLeft) / (2.0 * stepUV.x);
                float dTex_dV = (hUp - hDown) / (2.0 * stepUV.y);

                float3 modifiedTangentWS = tangentWS + normalWS * (dTex_dU + dNoise_dU);
                float3 modifiedBitangentWS = bitangentWS + normalWS * (dTex_dV + dNoise_dV);

                float3 finalNormalWS = -normalize(cross(modifiedTangentWS, modifiedBitangentWS));

                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                float4 shadowCoord = input.screenPos;
                #else
                float4 shadowCoord = TransformWorldToShadowCoord(input.finalPosWS);
                #endif

                float4 texColor = SAMPLE_TEXTURE2D(_ActivationTex, sampler_ActivationTex, input.uv);

                return ShadePearl(
                lerp(_ActivationLayerColor.rgb, _BaseColor.rgb, pixelActivation),
                _MetallicStrength,
                lerp(_ActivationLayerSmoothness, _Smoothness, pixelActivation),
                finalNormalWS,
                viewDirWS,
                shadowCoord,
                input.finalPosWS,
                lerp(_ActivationLayerColor.rgb, texColor.rgb, pixelActivation),
                lerp(_ActivationLayerColor.rgb, _PearlColorEdge.rgb, pixelActivation),
                _PearlSpread,
                _MixingPearlSpecular,
                _MixingPearlNormalPow,
                _MixingShadowValue);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.0

            #pragma vertex ShadowPassVertexCustom
            #pragma fragment ShadowPassFragmentCustom

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            float4 GetShadowPositionHClip(ShadowAttributes v)
            {
                float3 basePosWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

                float3 texDisplacedPosWS = GetDisplacedPositionWS(basePosWS, normalWS, v.uv);

                float h0_noise = GetNoiseHeight(texDisplacedPosWS, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float3 finalPosWS = texDisplacedPosWS + normalWS * h0_noise;

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - finalPosWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(finalPosWS, normalWS, lightDirectionWS));

                #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                return positionCS;
            }

            ShadowVaryings ShadowPassVertexCustom(ShadowAttributes input)
            {
                ShadowVaryings output;
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }

            float4 ShadowPassFragmentCustom(ShadowVaryings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }
}