using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Halo.App.Rendering;
using Halo.App.Settings.ViewModels;
using Halo.Core.Interaction;

namespace Halo.App.Settings.Views;

/// <summary>
/// The ring editor page: a live preview of the ring (the same renderer as the overlay, in editor
/// mode), the selected slot's inspector and a keyboard-friendly slot list.
/// </summary>
internal partial class RingPage : UserControl
{
    private RingCanvas? _canvas;
    private RingEditorViewModel? _model;

    public RingPage()
    {
        InitializeComponent();
        DataContextChanged += (_, _) => Attach(DataContext as RingEditorViewModel);
        Unloaded += (_, _) => Attach(null);
        Loaded += (_, _) => Attach(DataContext as RingEditorViewModel);
    }

    private void Attach(RingEditorViewModel? model)
    {
        if (ReferenceEquals(model, _model) && _canvas is not null) return;
        if (_model is not null) _model.Preview.Changed -= Resize;
        _model = model;
        CanvasHost.Child = null;
        _canvas = null;
        if (model is null) return;
        _canvas = new RingCanvas(model.Artwork) { Model = model.Preview };
        _canvas.MouseLeftButtonDown += OnCanvasClick;
        _canvas.MouseMove += OnCanvasMove;
        _canvas.MouseLeave += (_, _) => Hover(null);
        CanvasHost.Child = new Viewbox { Child = _canvas, Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly, Margin = new Thickness(12) };
        model.Preview.Changed += Resize;
        Resize();
    }

    /// <summary>Sizes the canvas to the ring (plus label room); the view box scales it down to fit.</summary>
    private void Resize()
    {
        if (_canvas is null || _model is null) return;
        var m = _model.Preview.Layout.Metrics;
        var side = (m.OuterRadius + (_model.Preview.LabelMode == Halo.Core.LabelMode.Always ? 110 : 40) * m.Scale) * 2;
        if (Math.Abs(_canvas.Width - side) > 0.5) _canvas.Width = _canvas.Height = side;
    }

    private void OnCanvasClick(object sender, MouseButtonEventArgs e)
    {
        if (_canvas is null || _model is null) return;
        switch (_canvas.HitTest(e.GetPosition(_canvas)))
        {
            case HitTarget.SlotHit hit when e.ClickCount >= 2 && _model.Slots[hit.Index].IsFolder:
                _model.EnterFolder(hit.Index);
                break;
            case HitTarget.SlotHit hit:
                _model.SelectedIndex = hit.Index;
                SlotList.Focus();
                break;
            case HitTarget.Hub when _model.IsInFolder:
                _model.BackCommand.Execute(null);
                break;
        }
    }

    private void OnCanvasMove(object sender, MouseEventArgs e)
    {
        if (_canvas is null) return;
        Hover(_canvas.HitTest(e.GetPosition(_canvas)) is HitTarget.SlotHit hit ? hit.Index : null);
    }

    private void Hover(int? slot)
    {
        if (_model is null || _model.Preview.Highlighted == slot) return;
        _model.Preview.Highlighted = slot;
        _model.Preview.NotifyChanged();
    }
}
