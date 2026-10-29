Shader "Prototype/NoiseWave_VertexNormalCalculation_02"
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
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            HLSLPROGRAM
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma vertex vert
            #pragma fragment frag

            #include "./Includes/PearlShading.hlsl"

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

            float _NoiseScale;
            float _NoiseSpeed;
            float _NoiseAmount;
            CBUFFER_END

            Varyings vert(Attributes v)
            {
                Varyings o;

                // 1. Отримуємо тангенс та бітангенс для правильного зсуву сусідніх точок
                float3 tangent = v.tangentOS.xyz;
                float3 bitangent = cross(v.normalOS, tangent) * v.tangentOS.w * unity_WorldTransformParams.w;

                // 2. Визначаємо невеликий відступ для пошуку сусідніх точок
                float offset = 0.01;
                float3 p0 = v.positionOS.xyz;
                float3 p1 = p0 + tangent * offset;
                float3 p2 = p0 + bitangent * offset;

                // 3. Рахуємо висоту (шум) для основної точки та двох сусідніх
                float h0 = GetNoiseHeight(p0, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h1 = GetNoiseHeight(p1, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);
                float h2 = GetNoiseHeight(p2, _Time.y, _NoiseScale, _NoiseSpeed, _NoiseAmount);

                // 4. Піднімаємо всі три точки
                float3 dispP0 = p0 + v.normalOS * h0;
                float3 dispP1 = p1 + v.normalOS * h1;
                float3 dispP2 = p2 + v.normalOS * h2;

                // 5. Знаходимо нові вектори від основної точки до сусідніх
                float3 newTangent = normalize(dispP1 - dispP0);
                float3 newBitangent = normalize(dispP2 - dispP0);

                // 6. Розраховуємо нову нормаль через векторний добуток
                float3 newNormalOS = -normalize(cross(newTangent, newBitangent));

                // Стандартні розрахунки, але тепер передаємо нову позицію та нову нормаль
                VertexPositionInputs vertexInput = GetVertexPositionInputs(dispP0);

                // Замість оригінальної v.normalOS передаємо нашу newNormalOS
                VertexNormalInputs normalInput = GetVertexNormalInputs(newNormalOS, v.tangentOS);
                // VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                o.positionWS = vertexInput.positionWS;
                o.positionCS = vertexInput.positionCS;
                o.uv = v.uv;
                o.normalWS = normalInput.normalWS;
                o.viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);
                o.shadowCoord = GetShadowCoord(vertexInput);

                return o;
            }

            half4 frag(Varyings input) : SV_Target
            {
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
    }
}