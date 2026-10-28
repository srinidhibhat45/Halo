using System.Windows;
using System.Windows.Automation;

namespace Halo.App.Settings.Dialogs;

/// <summary>Asks for a line (or block) of text: a web address, a snippet, a script, a prompt.</summary>
internal partial class PromptWindow : Window
{
    public PromptWindow(string title, string message, string initial, bool multiline, Window? owner)
    {
        InitializeComponent();
        Owner = owner;
        Title = title;
        Message.Text = message;
        Input.Text = initial;
        AutomationProperties.SetName(Input, message);
        if (multiline)
        {
            Input.AcceptsReturn = true;
            Input.AcceptsTab = true;
            Input.TextWrapping = TextWrapping.Wrap;
            Input.MinHeight = 140;
            Input.FontFamily = new System.Windows.Media.FontFamily("Cascadia Mono, Consolas");
            OkButton.IsDefault = false;
        }
        Loaded += (_, _) =>
        {
            Input.Focus();
            Input.SelectAll();
        };
    }

    /// <summary>Shows the dialog; the text entered, or null when cancelled or left empty.</summary>
    public string? Ask() => ShowDialog() == true && !string.IsNullOrWhiteSpace(Input.Text) ? Input.Text : null;

    private void OnOk(object sender, RoutedEventArgs e) => DialogResult = true;
}
