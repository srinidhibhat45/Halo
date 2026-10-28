namespace Halo.App.Platform;

/// <summary>
/// One Halo per user session: a named mutex held for the app's lifetime. Starting Halo again
/// signals the running copy (which opens its settings) and exits.
/// </summary>
internal sealed class SingleInstance : IDisposable
{
    private const string MutexName = @"Local\Halo.SingleInstance.7C4E2B19";
    private const string ActivateEventName = @"Local\Halo.Activate.7C4E2B19";

    private readonly Mutex _mutex;
    private readonly EventWaitHandle _activate;
    private RegisteredWaitHandle? _wait;

    private SingleInstance(Mutex mutex, EventWaitHandle activate)
    {
        _mutex = mutex;
        _activate = activate;
    }

    /// <summary>Becomes the running instance, or returns null when another one already is.</summary>
    public static SingleInstance? TryAcquire()
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        if (!createdNew)
        {
            mutex.Dispose();
            return null;
        }
        return new SingleInstance(mutex, new EventWaitHandle(false, EventResetMode.AutoReset, ActivateEventName));
    }

    /// <summary>Asks the running instance to come forward (open its settings).</summary>
    public static void SignalRunningInstance()
    {
        if (!EventWaitHandle.TryOpenExisting(ActivateEventName, out var activate)) return;
        using (activate) activate.Set();
    }

    /// <summary>Calls <paramref name="onActivate"/> (on a thread-pool thread) whenever another launch signals.</summary>
    public void ListenForActivation(Action onActivate) =>
        _wait = ThreadPool.RegisterWaitForSingleObject(_activate, (_, _) => onActivate(), null, Timeout.Infinite, executeOnlyOnce: false);

    /// <summary>Releases the mutex; call on the thread that acquired it (the main thread).</summary>
    public void Dispose()
    {
        _wait?.Unregister(null);
        _activate.Dispose();
        _mutex.ReleaseMutex();
        _mutex.Dispose();
    }
}
