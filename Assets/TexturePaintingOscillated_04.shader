Shader "Flexus/TexturePaintingOscillated_04"
{
    Properties
    {
        _MainTex ("Current Height (Read)", 2D) = "gray" {}
        _AgentUvPosition ("Agent UV Position", Vector) = (0.5, 0.5, 0, 0)
        _PreviousAgentUvPosition ("Previous Agent UV", Vector) = (0.5, 0.5, 0, 0)
        _AgentRadius ("Agent Radius", Range(0.01, 1.0)) = 0.1
        _StampStrength ("Stamp Strength", Range(0.0, 1.0)) = 0.05

        [Header(Oscillation and Damping)]
        _Damping ("Damping Speed (Швидкість затухання)", Range(0.001, 0.5)) = 0.05
        _Viscosity ("Viscosity / Frequency (Частота осциляцій)", Range(0.005, 0.5)) = 0.08
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

            sampler2D _MainTex;

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
                float2 state = tex2D(_MainTex, i.uv).rg;
                float currentHeight = state.r;
                float prevHeight = state.g;



                //oscillation
                float displacement = currentHeight - 0.5;
                float velocity = currentHeight - prevHeight;

                float oscillatedHeight = currentHeight + velocity * (1.0 - _Damping) - displacement * _Viscosity;
                oscillatedHeight = saturate(oscillatedHeight);
                float nextPrevHeight = currentHeight;


                float2 a = _PreviousAgentUvPosition.xy;
                float2 b = _AgentUvPosition.xy;
                float2 ba = b - a;
                float moveLenSq = dot(ba, ba);

                if (moveLenSq < 0.0000000001)
                {
                    return float4(oscillatedHeight, nextPrevHeight, oscillatedHeight, 1.0);
                }

                float2 moveDir = normalize(ba);

                // Closest point on the movement line a b
                float2 pa = i.uv - a;
                float h = saturate(dot(pa, ba) / moveLenSq);
                float2 closest = a + ba * h;

                //from current pixel to line projection point
                float2 diff = i.uv - closest;
                float dist = length(diff);

                if (dist >= _AgentRadius)
                {
                    return float4(oscillatedHeight, nextPrevHeight, oscillatedHeight, 1.0);
                }

                float2 pixelDir = diff / max(dist, 0.00001);

                // Normalized radial distance
                float r = dist / _AgentRadius;

                float dirDot = dot(pixelDir, moveDir);

                // Smooth directional weights. sum=1
                float front = smoothstep(0.0, 1.0, dirDot);
                float back = smoothstep(0.0, 1.0, -dirDot);
                float side = 1.0 - front - back;

                // central brash curve form
                float coreToRim = smoothstep(0.08, 0.52, r);



                float rimTarget = (1.00 * front) + (0.75 * side) + (0.35 * back);

                // Center of the brush (coreToRim = 0) carves down toward 0.0
                float targetHeight = coreToRim * rimTarget;

                // removing trails. r=1 -> no _StampStrength
                float outerFade = 1.0 - smoothstep(0.45, 1.0, r);

                float weight = saturate(_StampStrength * outerFade);
                float newHeight = saturate(lerp(currentHeight, targetHeight, weight));

                oscillatedHeight = saturate(lerp(oscillatedHeight, newHeight, weight));
                nextPrevHeight = lerp(nextPrevHeight, oscillatedHeight, weight); //suppress vibration

                return float4(oscillatedHeight, nextPrevHeight, oscillatedHeight, 1.0);
            }
            ENDHLSL
        }
    }
}