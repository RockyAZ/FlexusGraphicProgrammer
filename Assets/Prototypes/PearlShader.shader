Shader "Prototype/PearlShader"
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
      Tags
      {
        "LightMode" = "UniversalForward"
      }
      HLSLPROGRAM
      #pragma vertex vert
      #pragma fragment frag
      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
      
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
      half4 _PearlColorCenter;
      half4 _PearlColorEdge;
      half _PearlSpread;
      half _MixingPearlSpecular;
      half _MixingPearlNormalPow;
      half _MixingShadowValue;
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
        half3 albedo = _BaseColor.rgb;
        half metallic = _MetallicStrength;
        half smoothness = _Smoothness;

        half3 N = normalize(input.normalWS);
        half3 V = input.viewDirWS;

        Light mainLight = GetMainLight(input.shadowCoord);
        half3 L = normalize(mainLight.direction);
        half3 H = normalize(L + V); //Halfvector for specular calculations, cheaper than R = 2 * dot(N, L) * N - L

        // Calculate light intensity including shadows
        half attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
        half3 lightColor = mainLight.color * attenuation;

        //pearl calculation
        half NdotV = saturate(dot(N, V));
        half pearlFactor = pow(1.0 - NdotV, _PearlSpread);
        half3 iridescenceColor = lerp(_PearlColorCenter.rgb, _PearlColorEdge.rgb, pearlFactor);

        half3 dielectricSpec = half3(0.04, 0.04, 0.04); // Non-metals reflect ~4 % of light
        half3 baseSpecular = lerp(dielectricSpec, albedo, metallic);

        half3 specularColor = lerp(baseSpecular, iridescenceColor, _MixingPearlSpecular);

        half NdotL = dot(N, L);
        half NdotLSaturate = saturate(NdotL);

        //diffuse
        half3 diffuseColor = albedo * (1.0 - metallic);
        half mixingPearl = pow(NdotV, _MixingPearlNormalPow);
        diffuseColor = lerp(diffuseColor, iridescenceColor, mixingPearl);

        half diffuseMultiplier = saturate(NdotL + _MixingShadowValue);
        half3 directDiffuse = diffuseColor * diffuseMultiplier;
        half3 indirectDiffuse = SampleSH(N) * diffuseColor;

        
        half NdotH = saturate(dot(N, H));

        half3 viewReflect = reflect(-V, N);
        half perceptualRoughness = 1.0 - smoothness;

        //baked cubemap reflections
        half3 envReflection = GlossyEnvironmentReflection(viewReflect, input.positionWS, perceptualRoughness, 1.0);
        half3 indirectSpecular = envReflection * specularColor;

        half specPower = exp2(10.0 * smoothness + 1.0);

        half3 directSpecular = specularColor * pow(NdotH, specPower) * smoothness;

        half3 finalColor = (directDiffuse + directSpecular) * lightColor + indirectDiffuse + indirectSpecular;
        return half4(finalColor, 1.0);
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