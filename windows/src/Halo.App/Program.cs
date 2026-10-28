using Halo.App.Platform;
using Velopack;

namespace Halo.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // Velopack's install/update/uninstall hooks must run before anything else; during those
        // hooks it exits the process itself.
        VelopackApp.Build()
            .OnBeforeUninstallFastCallback(_ => StartWithWindows.Set(false))
            .Run();

        using var instance = SingleInstance.TryAcquire();
        if (instance is null)
        {
            // Already running: ask it to show its settings, then leave.
            SingleInstance.SignalRunningInstance();
            return 0;
        }

        var app = new HaloApplication(instance, startedAtSignIn: args.Contains(StartWithWindows.BackgroundArgument));
        app.InitializeComponent();
        return app.Run();
    }
}
