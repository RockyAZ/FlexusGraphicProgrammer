Shader "Prototype/TexturePainting_03 Blend One One 2"
{
    Properties
    {
        _AgentUvPosition ("Agent UV Position", Vector) = (0.5, 0.5, 0, 0)
        _AgentRadius ("Agent Radius", Range(0.01, 20.0)) = 0.1
        _StampStrength ("Stamp Strength", Float) = 0.05
        
        // Новое свойство для контроля ширины плавного затухания по краям
        _RimFade ("Rim Fade Width", Range(0.01, 0.5)) = 0.25
    }
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
        }

        Blend One One 
        ZWrite Off
        ZTest Always
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _AgentUvPosition;
                float _AgentRadius;
                float _StampStrength;
                float _RimFade; // Не забываем добавить в CBUFFER
            CBUFFER_END

            Varyings vert (Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            float4 frag (Varyings i) : SV_Target
            {
                float dist = distance(i.uv, _AgentUvPosition.xy);

                // Нормализуем дистанцию от 0 до 1. 
                // saturate() зажмет всё, что больше радиуса, ровно в 1.0
                float t = saturate(dist / _AgentRadius);

                // Базовая форма: гладкая чаша от -1 (в центре) до 1 (на краю). 
                // t = 0.0 -> -cos(0) = -1
                // t = 0.5 -> -cos(PI/2) = 0
                // t = 1.0 -> -cos(PI) = 1
                float baseShape = -cos(t * PI);
                
                // Плавное затухание от 1 до 0 на самом краю.
                // Начинает угасать от (1.0 - _RimFade) и становится строгим 0 при t = 1.0
                float edgeFade = 1.0 - smoothstep(1.0 - _RimFade, 1.0, t);

                // Комбинируем. За пределами радиуса t всегда равно 1, 
                // значит edgeFade строго равно 0. Никакие "if" не нужны!
                float falloff = baseShape * edgeFade;

                // Итоговое значение, которое запишется в красный канал
                float writeValue = falloff * _StampStrength;

                return float4(writeValue, 0, 0, 0);
            }
            ENDHLSL
        }
    }
}