using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Halo.App.Rendering;
using Halo.App.Settings.ViewModels;

namespace Halo.App.Settings.Views;

/// <summary>Appearance settings with a live preview drawn by the overlay's own renderer.</summary>
internal partial class AppearancePage : UserControl
{
    public AppearancePage()
    {
        InitializeComponent();
        DataContextChanged += (_, _) =>
        {
            if (DataContext is not AppearanceViewModel model) return;
            var side = model.Preview.Layout.Metrics.OuterRadius * 2 + 120;
            var canvas = new RingCanvas(model.Artwork) { Model = model.Preview, Width = side, Height = side };
            PreviewHost.Child = new Viewbox { Child = canvas, Stretch = Stretch.Uniform, Margin = new Thickness(12) };
        };
    }
}
