using System.Windows;
using Halo.App.Settings.ViewModels;

namespace Halo.App.Settings;

/// <summary>"Halo Settings": the rings (Everywhere and app rings) and the General, Appearance and About pages.</summary>
internal partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsViewModel model)
    {
        Model = model;
        InitializeComponent();
        DataContext = model;
        // Recording a shortcut must stop as soon as the window loses focus.
        Deactivated += (_, _) => model.General.CancelRecording();
        Closed += (_, _) => model.Dispose();
    }

    public SettingsViewModel Model { get; }

    /// <summary>Brings the window to the front, restoring it if minimised.</summary>
    public void Present()
    {
        if (!IsVisible) Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }
}
