using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using Halo.App.Settings.ViewModels;

namespace Halo.App.Settings.Dialogs;

/// <summary>A searchable, grouped list dialog over a <see cref="PickerViewModel"/>.</summary>
internal partial class PickerWindow : Window
{
    private readonly PickerViewModel _model;

    public PickerWindow(PickerViewModel model, Window? owner)
    {
        _model = model;
        InitializeComponent();
        Owner = owner;
        DataContext = model;
        CollectionViewSource.GetDefaultView(model.Items).GroupDescriptions.Add(new PropertyGroupDescription(nameof(PickerItem.Group)));
        Loaded += (_, _) => SearchBox.Focus();
    }

    /// <summary>Shows the dialog; the chosen row, or null when cancelled.</summary>
    public PickerItem? Choose() => ShowDialog() == true ? _model.Selected : null;

    private void OnChoose(object sender, RoutedEventArgs e)
    {
        if (_model.Selected is not { IsEnabled: true }) return;
        DialogResult = true;
    }

    /// <summary>Arrow keys in the search box move through the list.</summary>
    private void OnSearchKeyDown(object sender, KeyEventArgs e)
    {
        var enabled = _model.Items.Where(i => i.IsEnabled).ToList();
        if (enabled.Count == 0 || e.Key is not (Key.Down or Key.Up)) return;
        var index = _model.Selected is { } current ? enabled.IndexOf(current) : -1;
        index = e.Key == Key.Down ? Math.Min(index + 1, enabled.Count - 1) : Math.Max(index - 1, 0);
        _model.Selected = enabled[index];
        List.ScrollIntoView(_model.Selected);
        e.Handled = true;
    }
}
