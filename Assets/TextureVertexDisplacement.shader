Shader "Flexus/TextureVertexDisplacement"
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
        _DisplacementStrength ("Displacement Strength", Float) = 1.0
        _DisplacementMax ("Max value of displacement", Float) = 10.0
    }

    SubShader
    {
        Tags {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }
        LOD 100

        HLSLINCLUDE
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
        #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
        #pragma multi_compile_fragment _ _SHADOWS_SOFT
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

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
        CBUFFER_END

        float convert_to_minusone_one(float value)
        {
            return value * 2.0 - 1.0;
        }

        float3 GetDisplacedPositionOS(float3 positionOS, float3 normalOS, float2 uv)
        {
            float rawHeight = SAMPLE_TEXTURE2D_LOD(_DisplacementMap, sampler_DisplacementMap, uv, 0).r;
            float h0 = convert_to_minusone_one(rawHeight) * _DisplacementStrength;
            return positionOS + (normalOS * h0);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "./Includes/PearlShading.hlsl"

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

                float3 displacedPositionOS = GetDisplacedPositionOS(v.positionOS.xyz, v.normalOS, v.uv);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(displacedPositionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                o.positionWS = vertexInput.positionWS;
                o.positionCS = vertexInput.positionCS;
                o.uv = v.uv;

                o.normalWS = normalInput.normalWS;
                o.tangentWS = normalInput.tangentWS;
                o.bitangentWS = normalInput.bitangentWS;

                o.viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);
                o.shadowCoord = GetShadowCoord(vertexInput);

                return o;
            }

            float4 frag(v2f input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS);
                float3 bitangentWS = normalize(input.bitangentWS);

                float2 texelSize = _DisplacementMap_TexelSize.xy;

                float h0 = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv).r * _DisplacementStrength;
                float hU = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv + float2(texelSize.x, 0)).r * _DisplacementStrength;
                float hV = SAMPLE_TEXTURE2D(_DisplacementMap, sampler_DisplacementMap, input.uv + float2(0, texelSize.y)).r * _DisplacementStrength;

                h0 = convert_to_minusone_one(h0);
                hU = convert_to_minusone_one(hU);
                hV = convert_to_minusone_one(hV);

                // height difference / distance = gradient of displacement
                float3 modifiedTangentWS = tangentWS + normalWS * ((hU - h0) / texelSize.x);
                float3 modifiedBitangentWS = bitangentWS + normalWS * ((hV - h0) / texelSize.y);

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

            float4 GetShadowPositionHClip(ShadowAttributes input)
            {
                float3 displacedPositionOS = GetDisplacedPositionOS(input.positionOS.xyz, input.normalOS, input.uv);

                float3 positionWS = TransformObjectToWorld(displacedPositionOS);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

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