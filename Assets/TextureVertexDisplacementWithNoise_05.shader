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

    }

    SubShader
    {
        Tags {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }
        LOD 100

        HLSLINCLUDE //shared block for shadow pass
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
        #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
        #pragma multi_compile_fragment _ _SHADOWS_SOFT
        #include "./Includes/PearlShading.hlsl"

        TEXTURE2D(_DisplacementMap);
        SAMPLER(sampler_DisplacementMap);

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
        CBUFFER_END

        float convert_to_minusone_one(float value)
        {
            return value * 2.0 - 1.0;
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

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float3 viewDirWS : TEXCOORD5;
                float4 shadowCoord : TEXCOORD6;
            };

            v2f vert(Attributes v)
            {
                v2f o;

                float3 basePosWS = TransformObjectToWorld(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                float3 texDisplacedPosWS = GetDisplacedPositionWS(basePosWS, normalInput.normalWS, v.uv);

                float h0_noise = GetNoiseHeight(texDisplacedPosWS, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float3 finalPosWS = texDisplacedPosWS + normalInput.normalWS * h0_noise;

                o.positionWS = texDisplacedPosWS; // pre noise WS pos so frag noise matches vert noise
                o.positionCS = TransformWorldToHClip(finalPosWS);
                o.uv = v.uv;

                o.normalWS    = normalInput.normalWS;
                o.tangentWS   = normalInput.tangentWS;
                o.bitangentWS = normalInput.bitangentWS;

                o.viewDirWS   = GetWorldSpaceNormalizeViewDir(finalPosWS);
                o.shadowCoord = TransformWorldToShadowCoord(finalPosWS);

                return o;
            }

            float4 frag(v2f input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS);
                float3 bitangentWS = normalize(input.bitangentWS);

                //noise gradients
                float3 p0 = input.positionWS;
                float3 p1 = p0 + tangentWS * _OffsetTangents;
                float3 p2 = p0 + bitangentWS * _OffsetTangents;

                float h0_noise = GetNoiseHeight(p0, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h1_noise = GetNoiseHeight(p1, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h2_noise = GetNoiseHeight(p2, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);

                float dNoise_dU = (h1_noise - h0_noise) / _OffsetTangents;
                float dNoise_dV = (h2_noise - h0_noise) / _OffsetTangents;


                float2 texelSize = _DisplacementMap_TexelSize.xy;

                //sampling displacement map
                float rawH0 = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv).r;
                float rawHU = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv + float2(texelSize.x, 0)).r;
                float rawHV = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv + float2(0, texelSize.y)).r;

                float h0_tex = convert_to_minusone_one(rawH0) * _DisplacementStrength;
                float hU_tex = convert_to_minusone_one(rawHU) * _DisplacementStrength;
                float hV_tex = convert_to_minusone_one(rawHV) * _DisplacementStrength;

                float dTex_dU = (hU_tex - h0_tex) / texelSize.x;
                float dTex_dV = (hV_tex - h0_tex) / texelSize.y;


                // height difference / distance = gradient of displacement
                float3 modifiedTangentWS   = tangentWS + normalWS * (dTex_dU + dNoise_dU);
                float3 modifiedBitangentWS = bitangentWS + normalWS * (dTex_dV + dNoise_dV);

                float3 finalNormalWS = -normalize(cross(modifiedTangentWS, modifiedBitangentWS));

                return ShadePearl(
                _BaseColor.rgb,
                _MetallicStrength,
                _Smoothness,
                finalNormalWS,
                input.viewDirWS,
                input.shadowCoord,
                input.positionWS,
                _PearlColorCenter.rgb,
                _PearlColorEdge.rgb,
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