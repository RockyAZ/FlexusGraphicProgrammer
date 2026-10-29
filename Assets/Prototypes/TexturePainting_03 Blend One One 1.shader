Shader "Prototype/TexturePainting_03 Blend One One 1"
{
    Properties
    {
        _AgentUvPosition ("Agent UV Position", Vector) = (0.5, 0.5, 0, 0)
        _AgentRadius ("Agent Radius", Float) = 0.1
        _StampStrength ("Stamp Strength", Float) = 0.05
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

                if (dist > _AgentRadius)
                {
                    return float4(0, 0, 0, 0); 
                }

                // Создаем мягкий градиент (falloff): 1 в центре агента, 0 на краю радиуса
                float falloff = 1.0 - (dist / _AgentRadius);
                
                // Итоговое значение, которое запишется в красный канал (вдавливание)
                float writeValue = falloff * _StampStrength;

                return float4(writeValue, 0, 0, 0);
            }
            ENDHLSL
        }
    }
}