using System;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
[Serializable]
public class SceneElement
{
    public GameObject GameObject;
    public string Title;
}
public class SceneController : MonoBehaviour
{
    [SerializeField] private Button nextButton;
    [SerializeField] private Button previousButton;
    [SerializeField] private TextMeshProUGUI title;
    [SerializeField] private SceneElement[] sceneElements;

    private int _currentId;
    void OnEnable()
    {
        nextButton.onClick.AddListener(OnNextClick);
        previousButton.onClick.AddListener(OnPreviousClick);
        _currentId = 0;
        UpdateView();
    }
    void OnDisable()
    {
        nextButton.onClick.RemoveListener(OnNextClick);
        previousButton.onClick.RemoveListener(OnPreviousClick);
    }

    void OnNextClick()
    {
        _currentId = (_currentId + 1) % sceneElements.Length;
        UpdateView();
    }
    void OnPreviousClick()
    {
        _currentId = (_currentId - 1 + sceneElements.Length) % sceneElements.Length;
        UpdateView();
    }

    private void UpdateView()
    {
        foreach (var tmp in sceneElements)
        {
            tmp.GameObject.SetActive(false);
        }
        sceneElements[_currentId].GameObject.SetActive(true);
        title.text = sceneElements[_currentId].Title;
    }
}
