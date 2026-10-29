Shader "Flexus/MaterialShader_01"
{
  Properties
  {
    _BaseColor("Base Color", Color) = (1, 1, 1, 1)
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
  }

  SubShader
  {
    Tags
    {
      "RenderType" = "Opaque"
      "Queue" = "Geometry"
      "RenderPipeline" = "UniversalPipeline"
    }

    Pass
    {
      Name "ForwardLit"
      Tags
      {
        "LightMode" = "UniversalForward"
      }
      HLSLPROGRAM
      #pragma vertex vert
      #pragma fragment frag
      #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
      #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
      #pragma multi_compile_fragment _ _SHADOWS_SOFT
      #include "./Includes/PearlShading.hlsl"

      struct appdata {
        float4 positionOS : POSITION;
        float2 uv : TEXCOORD0;
        float3 normalOS : NORMAL;
        float4 tangentOS : TANGENT;
      };
      struct v2f {
        float4 positionCS : SV_POSITION;
        float2 uv : TEXCOORD0;
        float3 positionWS : TEXCOORD1;
        float3 normalWS : TEXCOORD2;
        float3 viewDirWS : TEXCOORD3;
        float4 shadowCoord : TEXCOORD4;
      };

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
      CBUFFER_END

      v2f vert(appdata v) {
        v2f o;

        VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
        VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

        o.positionWS = vertexInput.positionWS;
        o.positionCS = vertexInput.positionCS;

        o.uv = v.uv;

        o.normalWS = normalInput.normalWS;

        o.viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);
        o.shadowCoord = GetShadowCoord(vertexInput);
        return o;
      }

      float4 frag(v2f input) : SV_Target {

        return ShadePearl(
        _BaseColor.rgb,
        _MetallicStrength,
        _Smoothness,
        input.normalWS,
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

      #pragma vertex ShadowPassVertex
      #pragma fragment ShadowPassFragment

      #pragma shader_feature_local_fragment _ALPHATEST_ON
      #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

      #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

      #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

      #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
      #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
      ENDHLSL
    }
  }
}