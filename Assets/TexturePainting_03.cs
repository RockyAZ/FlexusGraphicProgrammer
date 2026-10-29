using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.InputSystem;

public class TexturePainting_03 : MonoBehaviour
{
    public bool updateTextureWithoutTouching;
    public Vector2Int textureResolution = new Vector2Int(100, 100);

    private RenderTexture rtA;
    private RenderTexture rtB;
    private bool useRtA = true;
    public Material brushMaterial;
    public Material terrainMaterial;
    public string terrainMaterialTextureName = "_DisplacementMap";

    [Range(0f, 1f)]
    public float agentRadius = 0.05f;
    public float stampStrength = 0.1f;

    [Header("Plane")]
    public Transform plane;
    public BoxCollider boxCollider;

    private Vector3 _lastHitWorld;
    private bool _hasLastHit;
    private bool _hasFirstHit;
    private Vector3 _previousAgentPosition;

    private void Start()
    {
        rtA = new RenderTexture(textureResolution.x, textureResolution.y, 0, RenderTextureFormat.ARGBFloat);//RFloat
        rtB = new RenderTexture(textureResolution.x, textureResolution.y, 0, RenderTextureFormat.ARGBFloat);
        rtA.Create();
        rtB.Create();
        ClearToGray(rtA);
        ClearToGray(rtB);
        terrainMaterial.SetTexture(terrainMaterialTextureName, rtA);
    }

    private void ClearToGray(RenderTexture rt)
    {
        RenderTexture previousActive = RenderTexture.active;
        RenderTexture.active = rt;
        GL.Clear(false, true, new Color(0.5f, 0.5f, 0.5f, 1.0f));
        RenderTexture.active = previousActive;
    }
    void OnDestroy()
    {
        if (rtA != null)
            rtA.Release();
        if (rtB != null)
            rtB.Release();
    }

    void Update()
    {
        if (!TryGetPointerScreenPosition(out Vector2 screenPosition))
        {
            _hasFirstHit = false;
            if (updateTextureWithoutTouching)
            {
                brushMaterial.SetFloat("_StampStrength", 0);
                DrawChangeBuffer();
            }
            return;
        }

        if (!GetAgentUVPosition(screenPosition, out Vector2 agentUVPosition))
        {
            _hasFirstHit = false;
            if (updateTextureWithoutTouching)
            {
                brushMaterial.SetFloat("_StampStrength", 0);
                DrawChangeBuffer();
            }
            return;
        }

        if (!_hasFirstHit)//preventing bug with mouse replacing
            _previousAgentPosition = agentUVPosition + Vector2.one * 0.00001f;

        if (updateTextureWithoutTouching && Vector3.Distance(_previousAgentPosition, agentUVPosition) < 0.00001f)
        {
            _previousAgentPosition = agentUVPosition + Vector2.one * 0.00001f;
        }

        _hasFirstHit = true;

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

        //distance = Dot(P, A)
        float u = Vector3.Dot(from00_toLastHit, uAxis) / uLengthSq;
        float v = Vector3.Dot(from00_toLastHit, vAxis) / vLengthSq;

        if (u < 0f || u > 1f || v < 0f || v > 1f)
            return false;

        uv = new Vector2(1 - u, 1 - v);
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

    void OnDrawGizmos()
    {
        if (_hasLastHit)
        {
            Gizmos.color = Color.yellow;
            Gizmos.DrawSphere(_lastHitWorld, 0.05f);
            Gizmos.DrawRay(_lastHitWorld, Vector3.up * 100f);
        }
    }
    #endregion
}

