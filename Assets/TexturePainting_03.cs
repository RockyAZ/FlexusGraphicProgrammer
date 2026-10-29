using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Experimental.Rendering;

public class TexturePainting_03 : MonoBehaviour
{
    [SerializeField] private bool updateTextureWithoutTouching;
    [SerializeField] private Vector2Int textureResolution = new Vector2Int(256, 256);

    [SerializeField] private Material brushMaterial;
    [SerializeField] private Material terrainMaterial;
    [SerializeField] private string terrainMaterialTextureName = "_DisplacementMap";

    [Range(0f, 1f)]
    [SerializeField] private float agentRadius = 0.05f;
    [SerializeField] private float stampStrength = 0.1f;

    [Header("Plane")]
    [SerializeField] private Transform plane;
    [SerializeField] private BoxCollider boxCollider;

    private RenderTexture rtA;
    private RenderTexture rtB;
    private bool useRtA = true;

    private Vector3 _lastHitWorld;
    private bool _hasLastHit;
    private bool _hasFirstHit;
    private Vector2 _previousAgentPosition;

    private void Start()
    {
        GraphicsFormat format = SystemInfo.IsFormatSupported(
            GraphicsFormat.R32G32B32A32_SFloat,
            GraphicsFormatUsage.Render | GraphicsFormatUsage.Linear
        )
            ? GraphicsFormat.R32G32B32A32_SFloat
            : GraphicsFormat.R16G16B16A16_SFloat;

        rtA = CreateSimulationRT(format);
        rtB = CreateSimulationRT(format);

        ClearToZero(rtA);
        ClearToZero(rtB);
        terrainMaterial.SetTexture(terrainMaterialTextureName, rtA);
    }

    private void OnDisable()
    {
        if(rtA != null) ClearToZero(rtA);
        if(rtB != null) ClearToZero(rtB);
    }

    private RenderTexture CreateSimulationRT(GraphicsFormat format)
    {
        var desc = new RenderTextureDescriptor(textureResolution.x, textureResolution.y)
        {
            graphicsFormat = format,
            depthBufferBits = 0,
            msaaSamples = 1,
            sRGB = false
        };

        RenderTexture rt = new RenderTexture(desc)
        {
            filterMode = FilterMode.Bilinear,
            wrapMode = TextureWrapMode.Clamp
        };
        rt.Create();
        return rt;
    }

    private void ClearToZero(RenderTexture rt)
    {
        RenderTexture previousActive = RenderTexture.active;
        RenderTexture.active = rt;
        GL.Clear(false, true, Color.clear);
        RenderTexture.active = previousActive;
    }

    void OnDestroy()
    {
        if (rtA != null) rtA.Release();
        if (rtB != null) rtB.Release();
    }

    void Update()
    {
        if (!TryGetPointerScreenPosition(out Vector2 screenPosition) ||
            !GetAgentUVPosition(screenPosition, out Vector2 agentUVPosition))
        {
            _hasFirstHit = false;
            if (updateTextureWithoutTouching)
            {
                brushMaterial.SetFloat("_StampStrength", 0f);
                DrawChangeBuffer();
            }
            return;
        }

        if (!_hasFirstHit)
        {
            _previousAgentPosition = agentUVPosition;
            _hasFirstHit = true;
        }

        brushMaterial.SetVector("_AgentUvPosition", new Vector4(agentUVPosition.x, agentUVPosition.y, 0, 0));
        brushMaterial.SetVector("_PreviousAgentUvPosition", new Vector4(_previousAgentPosition.x, _previousAgentPosition.y, 0, 0));
        brushMaterial.SetFloat("_AgentRadius", agentRadius);
        brushMaterial.SetFloat("_StampStrength", stampStrength);

        DrawChangeBuffer();

        _previousAgentPosition = agentUVPosition;
    }

    private void DrawChangeBuffer()
    {
        RenderTexture readRT = useRtA ? rtA : rtB;
        RenderTexture writeRT = useRtA ? rtB : rtA;

        Graphics.Blit(readRT, writeRT, brushMaterial);
        useRtA = !useRtA;

        terrainMaterial.SetTexture(terrainMaterialTextureName, writeRT);
    }

    #region Scene agent position
    private bool TryGetPointerScreenPosition(out Vector2 screenPosition)
    {
        screenPosition = default;

        Mouse mouse = Mouse.current;
        if (mouse != null && mouse.leftButton.isPressed)
        {
            screenPosition = mouse.position.ReadValue();
            return true;
        }

        Touchscreen touchscreen = Touchscreen.current;
        if (touchscreen != null && touchscreen.primaryTouch.press.isPressed)
        {
            screenPosition = touchscreen.primaryTouch.position.ReadValue();
            return true;
        }

        return false;
    }

    private bool GetAgentUVPosition(Vector2 screenPosition, out Vector2 uv)
    {
        uv = Vector2.zero;
        _hasLastHit = false;

        if (plane == null || boxCollider == null)
            return false;

        Camera cam = Camera.main;
        if (cam == null)
            return false;

        Ray ray = cam.ScreenPointToRay(screenPosition);
        if (!Physics.Raycast(ray, out RaycastHit hit))
            return false;

        _lastHitWorld = hit.point;
        _hasLastHit = true;

        GetPlaneCorners(out Vector3 corner00, out Vector3 corner10, out Vector3 corner01, out _);

        Vector3 uAxis = corner10 - corner00;
        Vector3 vAxis = corner01 - corner00;
        Vector3 from00_toLastHit = _lastHitWorld - corner00;

        float uLengthSq = uAxis.sqrMagnitude;
        float vLengthSq = vAxis.sqrMagnitude;
        if (uLengthSq < Mathf.Epsilon || vLengthSq < Mathf.Epsilon)
            return false;

        float u = Vector3.Dot(from00_toLastHit, uAxis) / uLengthSq;
        float v = Vector3.Dot(from00_toLastHit, vAxis) / vLengthSq;

        if (u < 0f || u > 1f || v < 0f || v > 1f)
            return false;

        uv = new Vector2(1f - u, 1f - v);
        return true;
    }

    private void GetPlaneCorners(out Vector3 corner00, out Vector3 corner10, out Vector3 corner01, out Vector3 corner11)
    {
        Vector3 center = boxCollider.center;
        Vector3 half = boxCollider.size * 0.5f;

        corner00 = plane.TransformPoint(center + new Vector3(-half.x, 0f, -half.z));
        corner10 = plane.TransformPoint(center + new Vector3(half.x, 0f, -half.z));
        corner01 = plane.TransformPoint(center + new Vector3(-half.x, 0f, half.z));
        corner11 = plane.TransformPoint(center + new Vector3(half.x, 0f, half.z));
    }
    #endregion
}