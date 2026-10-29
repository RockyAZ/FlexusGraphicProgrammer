Shader "Prototype/test01"
{
    Properties
    {
        // A dark gray/red color by default so accumulation is obvious
        _Color ("Additive Color", Color) = (0.2, 0.0, 0.0, 1.0)
    }
    SubShader
    {
        // Transparent queue ensures it draws after opaque objects
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        
        // The core additive blending command
        Blend One One 
        
        // Turn off ZWrite so overlapping quads don't block each other
        ZWrite Off 
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            float4 _Color;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // Create a soft circle based on UV coordinates (center is 0.5, 0.5)
                float dist = distance(i.uv, float2(0.5, 0.5));
                
                // saturate clamps the value between 0 and 1
                // 1.0 at the center, fading to 0.0 at the edges
                float mask = saturate(1.0 - (dist * 2.0)); 
                
                // Multiply the chosen color by the soft circle mask
                return _Color * mask;
            }
            ENDCG
        }
    }
}