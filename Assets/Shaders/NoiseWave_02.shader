Shader "Flexus/NoiseWave_02"
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
        [Header(Noise)]
        _NoiseScale ("Noise Scale", Float) = 5.0
        _NoiseSpeed ("Noise Speed", Float) = 2.0
        _NoiseAmount ("Displacement Amount", Float) = 0.5
        _OffsetTangents ("Offset Tangent Bitangent", Range(0.00001, 15)) = 0.001
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        HLSLINCLUDE
        #include "./Includes/PearlShading.hlsl"

        CBUFFER_START(UnityPerMaterial)
        float4 _BaseColor;
        float _MetallicStrength;
        float _Smoothness;
        float4 _PearlColorCenter;
        float4 _PearlColorEdge;
        float _PearlSpread;
        float _MixingPearlSpecular;
        float _MixingPearlNormalPow;
        float _MixingShadowValue;

        float _NoiseScale;
        float _NoiseSpeed;
        float _NoiseAmount;
        float _OffsetTangents;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
      
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
                //calculate waves normal in fragment shader
                float3 origPositionOS : TEXCOORD4;
                float3 origNormalOS : TEXCOORD5;
                float4 origTangentOS : TEXCOORD6;
                float3 origBitangentOS : TEXCOORD7; //fragment shader optimization
            };

            Varyings vert(Attributes v)
            {
                Varyings o;

                float h0 = GetNoiseHeight(v.positionOS.xyz, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float3 newNoisePos = v.positionOS.xyz + v.normalOS * h0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(newNoisePos);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                o.positionWS = vertexInput.positionWS;
                o.positionCS = vertexInput.positionCS;
                o.uv = v.uv;
                o.normalWS = normalInput.normalWS;
                o.viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);

                o.origPositionOS = v.positionOS.xyz;
                o.origNormalOS = v.normalOS;
                o.origTangentOS = v.tangentOS;
                o.origBitangentOS = cross(v.normalOS, v.tangentOS.xyz) * v.tangentOS.w * unity_WorldTransformParams.w;

                return o;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float3 tangent = normalize(input.origTangentOS.xyz);
                float3 bitangent = normalize(input.origBitangentOS);

                float3 p0 = input.origPositionOS;
                float3 p1 = p0 + tangent * _OffsetTangents;
                float3 p2 = p0 + bitangent * _OffsetTangents;

                float h0 = GetNoiseHeight(p0, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h1 = GetNoiseHeight(p1, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h2 = GetNoiseHeight(p2, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);

                float3 dispP0 = p0 + input.origNormalOS * h0;
                float3 dispP1 = p1 + input.origNormalOS * h1;
                float3 dispP2 = p2 + input.origNormalOS * h2;

                float3 newTangent = normalize(dispP1 - dispP0);
                float3 newBitangent = normalize(dispP2 - dispP0);
                float3 newNormalOS = -normalize(cross(newTangent, newBitangent));

                float3 pixelNormalWS = normalize(TransformObjectToWorldNormal(newNormalOS));


                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                float4 shadowCoord = ComputeScreenPos(TransformWorldToHClip(input.positionWS));
                #else
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                #endif

                return ShadePearl(
                _BaseColor.rgb,
                _MetallicStrength,
                _Smoothness,
                pixelNormalWS,
                input.viewDirWS,
                shadowCoord,
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

        Pass {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex ShadowPassVertexCustom
            #pragma fragment ShadowPassFragment

            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            Varyings ShadowPassVertexCustom(Attributes input)
            {
                float h0 = GetNoiseHeight(input.positionOS.xyz, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                input.positionOS.xyz += input.normalOS * h0;
                return ShadowPassVertex(input);
            }
            ENDHLSL
        }
    }
}