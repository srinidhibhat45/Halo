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

        // --self-test <folder> (or HALO_SELF_TEST=<folder>, which survives being started by the
        // installer): start normally, check the first-run essentials, save a report, quit.
        var selfTest = Array.IndexOf(args, "--self-test") is var i and >= 0 && i + 1 < args.Length
            ? args[i + 1]
            : Environment.GetEnvironmentVariable("HALO_SELF_TEST") is { Length: > 0 } folder ? folder : null;
        var app = new HaloApplication(instance, startedAtSignIn: args.Contains(StartWithWindows.BackgroundArgument), selfTest);
        app.InitializeComponent();
        return app.Run();
    }
}
