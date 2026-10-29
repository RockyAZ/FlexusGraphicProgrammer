Shader "Flexus/TexturePaintingOscillated_04"
{
    Properties
    {
        _MainTex ("Current State (Read)", 2D) = "black" {}
        _AgentUvPosition ("Agent UV Position", Vector) = (0.5, 0.5, 0, 0)
        _PreviousAgentUvPosition ("Previous Agent UV", Vector) = (0.5, 0.5, 0, 0)
        _AgentRadius ("Agent Radius", Range(0.01, 1.0)) = 0.1
        _StampStrength ("Stamp Strength", Range(0.0, 1.0)) = 0.05

        [Header(Oscillation and Damping)]
        _Damping ("Damping Speed", Range(0.001, 0.5)) = 0.05
        _Viscosity ("Viscosity / Frequency", Range(0.005, 0.5)) = 0.08
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

            // Force 32-bit float texture read on Android
            TEXTURE2D_FLOAT(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
            float4 _AgentUvPosition;
            float4 _PreviousAgentUvPosition;
            float _AgentRadius;
            float _StampStrength;
            float _Damping;
            float _Viscosity;
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
                // state.r = signed displacement [-0.5, 0.5] (0.0 = flat)
                // state.g = signed velocity
                float2 state = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rg;
                float displacement = state.r;
                float velocity = state.g;

                // Update spring-damper oscillation directly around 0.0
                velocity = velocity * (1.0 - _Damping) - displacement * _Viscosity;
                float oscillatedDisp = clamp(displacement + velocity, -0.5, 0.5);

                if (_StampStrength <= 0.00001)
                {
                    return float4(oscillatedDisp, velocity, 0.0, 1.0);
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

                float2 diff = i.uv - closest;
                float dist = length(diff);

                if (dist >= _AgentRadius)
                {
                    return float4(oscillatedDisp, velocity, 0.0, 1.0);
                }

                float2 pixelDir = diff / max(dist, 0.0001);
                float r = dist / _AgentRadius;

                float dirDot = dot(pixelDir, moveDir);

                float front = smoothstep(0.0, 1.0, dirDot);
                float back  = smoothstep(0.0, 1.0, -dirDot);
                float side  = 1.0 - front - back;

                float coreToRim = smoothstep(0.08, 0.52, r);
                float rimTarget = (1.00 * front) + (0.75 * side) + (0.35 * back);

                // Convert target from [0, 1] into signed displacement [-0.5, 0.5]
                float targetDisp = (coreToRim * rimTarget) - 0.5;

                float outerFade = 1.0 - smoothstep(0.45, 1.0, r);
                float weight = saturate(_StampStrength * outerFade);

                float finalDisp = clamp(lerp(oscillatedDisp, targetDisp, weight), -0.5, 0.5);
                // Suppress velocity vibration under the brush
                float finalVel  = lerp(velocity, (finalDisp - displacement) * 0.25, weight);

                return float4(finalDisp, finalVel, 0.0, 1.0);
            }
            ENDHLSL
        }
    }
}