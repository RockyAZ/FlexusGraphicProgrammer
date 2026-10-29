Shader "Flexus/TexturePainting_03"
{
    Properties
    {
        _MainTex ("Current Height (Read)", 2D) = "gray" {}
        _AgentUvPosition ("Agent UV Position", Vector) = (0.5, 0.5, 0, 0)
        _PreviousAgentUvPosition ("Previous Agent UV", Vector) = (0.5, 0.5, 0, 0)
        _AgentRadius ("Agent Radius", Range(0.01, 1.0)) = 0.1
        _StampStrength ("Stamp Strength", Range(0.0, 1.0)) = 0.05
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend Off
        ZWrite Off
        ZTest Always
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma prefer_hlslcc gles
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

            TEXTURE2D_FLOAT(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
            float4 _AgentUvPosition;
            float4 _PreviousAgentUvPosition;
            float _AgentRadius;
            float _StampStrength;
            float _MaxLineSpeed;
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
                float currentHeight = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).r;

                if (_StampStrength <= 0.00001)
                {
                    return float4(currentHeight, currentHeight, currentHeight, 1.0);
                }

                float2 a = _PreviousAgentUvPosition.xy;
                float2 b = _AgentUvPosition.xy;
                float2 ba = b - a;
                float moveLenSq = dot(ba, ba);
                float2 closest;
                float2 moveDir;

                // Avoid tiny float divisions on mobile GPUs when finger is stationary or moving slowly
                if (moveLenSq < 0.000001)
                {
                    closest = b;
                    moveDir = float2(0.0, 0.0);
                }
                else
                {
                    moveDir = ba * rsqrt(moveLenSq);
                    float2 pa = i.uv - a;
                    float h = saturate(dot(pa, ba) / moveLenSq);
                    closest = a + ba * h;
                }

                //from current pixel to line projection point
                float2 diff = i.uv - closest;
                float dist = length(diff);

                if (dist >= _AgentRadius)
                {
                    return float4(currentHeight, currentHeight, currentHeight, 1.0);
                }

                float2 pixelDir = diff / max(dist, 0.0001);
                float r = dist / _AgentRadius; // Normalized radial distance

                float dirDot = dot(pixelDir, moveDir);

                // Smooth directional weights. sum=1
                float front = smoothstep(0.0, 1.0, dirDot);
                float back = smoothstep(0.0, 1.0, -dirDot);
                float side = 1.0 - front - back;

                // central brash curve form
                float coreToRim = smoothstep(0.08, 0.52, r);
                float rimTarget = (1.00 * front) + (0.50 * side) + (0.35 * back);

                // Shift from [0.0, 1.0] to signed [-0.5, 0.5] so 0.0 is flat and -0.5 is carved
                float targetHeight = (coreToRim * rimTarget) - 0.5;

                // Removing trails: r=1 -> no _StampStrength
                float outerFade = 1.0 - smoothstep(0.45, 1.0, r);

                float weight = saturate(_StampStrength * outerFade);

                // Clamp to signed [-0.5, 0.5] instead of saturate() [0.0, 1.0]
                float newHeight = clamp(lerp(currentHeight, targetHeight, weight), -0.5, 0.5);

                return float4(newHeight, 0.0, 0.0, 1.0);
            }
            ENDHLSL
        }
    }
}