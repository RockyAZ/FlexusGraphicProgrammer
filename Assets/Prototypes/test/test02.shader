Shader "Prototype/test02"
{
    Properties
    {
        // A dark gray/red color by default so accumulation is obvious
        _Color ("Additive Color", Color) = (0.2, 0.0, 0.0, 1.0)
        _BaseTex("Base Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }        
        
        // The core additive blending command
        // Blend One One 
        
        // Turn off ZWrite so overlapping quads don't block each other
        // ZWrite Off 
        // Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Standard naming convention in URP
            struct Attributes
            {
                float4 positionOS : POSITION; // OS = Object Space
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION; // CS = Clip Space
            };

            // CBUFFER is required for SRP Batcher compatibility
            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _BaseTex_ST; // ST handles Tiling and Offset for the texture
            CBUFFER_END

            // Proper URP texture declaration
            TEXTURE2D(_BaseTex);
            SAMPLER(sampler_BaseTex);

            Varyings vert (Attributes v)
            {
                Varyings o;
                
                // URP equivalent of UnityObjectToClipPos
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                
                // If you want to apply Tiling/Offset from the material inspector:
                // o.uv = v.uv * _BaseTex_ST.xy + _BaseTex_ST.zw;
                o.uv = v.uv; 
                
                return o;
            }

            float4 frag (Varyings i) : SV_Target
            {
                // Create a soft circle based on UV coordinates (center is 0.5, 0.5)
                float dist = distance(i.uv, float2(0.5, 0.5));
                
                // saturate clamps the value between 0 and 1
                // Fixed the missing minus sign here
                float mask = saturate(1.0 - (dist * 2.0)); 
                
                // If you want to actually use the _BaseTex you added, you would sample it like this:
                // float4 texColor = SAMPLE_TEXTURE2D(_BaseTex, sampler_BaseTex, i.uv);
                // return _Color * mask * texColor;

                // Multiply the chosen color by the soft circle mask
                return _Color * mask;
            }
            ENDHLSL
        }
    }
}