using UnityEngine;

public class RotateAround : MonoBehaviour
{
    [SerializeField] private float speed = 50f;
    [SerializeField] private Vector3 axis = Vector3.up;

    void Update()
    {
        transform.Rotate(axis, speed * Time.deltaTime);
    }
}