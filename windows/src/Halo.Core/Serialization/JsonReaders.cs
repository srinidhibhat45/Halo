using System.Text.Json;

namespace Halo.Core.Serialization;

/// <summary>JSON → model, mirroring the macOS app's (tolerant) <c>Decodable</c> conformances.</summary>
internal static class JsonReaders
{
    public static HaloConfig Config(JsonElement e)
    {
        RequireObject(e, "config");
        var defaults = new HaloConfig();
        return new HaloConfig
        {
            SchemaVersion = Try(e, "schemaVersion", v => (int?)v.GetInt32()) ?? HaloConfig.CurrentSchemaVersion,
            Settings = Try(e, "settings", Settings) ?? defaults.Settings,
            // The global ring is the one thing worth failing loudly for: a config without it is not ours.
            GlobalRing = Ring(Required(e, "globalRing")),
            AppProfiles = TryGet(e, "appProfiles", out var profiles) && profiles.ValueKind == JsonValueKind.Array
                ? profiles.EnumerateArray().Select(p => Attempt(() => Profile(p))).OfType<AppProfile>().ToArray()
                : [],
        };
    }

    public static AppSettings Settings(JsonElement e)
    {
        RequireObject(e, "settings");
        var d = new AppSettings();
        // `trigger` distinguishes "absent" (use the default) from an explicit null (the user cleared it).
        var trigger = e.TryGetProperty("trigger", out var t)
            ? (t.ValueKind == JsonValueKind.Null ? null : Attempt(() => KeyCombo(t)))
            : d.Trigger;
        return new AppSettings
        {
            Trigger = trigger,
            SelectionMode = TryEnum(e, "selectionMode", d.SelectionMode),
            HoldThreshold = AppSettings.HoldThresholdRange.Clamp(TryDouble(e, "holdThreshold") ?? d.HoldThreshold),
            Theme = TryEnum(e, "theme", d.Theme),
            RingScale = AppSettings.RingScaleRange.Clamp(TryDouble(e, "ringScale") ?? d.RingScale),
            LabelMode = TryEnum(e, "labelMode", d.LabelMode),
            Placement = TryEnum(e, "placement", d.Placement),
            AnimationSpeed = AppSettings.AnimationSpeedRange.Clamp(TryDouble(e, "animationSpeed") ?? d.AnimationSpeed),
            Accent = Try(e, "accent", Color) ?? d.Accent,
            HapticsEnabled = TryBool(e, "hapticsEnabled") ?? d.HapticsEnabled,
            SoundsEnabled = TryBool(e, "soundsEnabled") ?? d.SoundsEnabled,
            ShowMenuBarIcon = TryBool(e, "showMenuBarIcon") ?? d.ShowMenuBarIcon,
            LaunchAtLogin = TryBool(e, "launchAtLogin") ?? d.LaunchAtLogin,
            AppRingsEnabled = TryBool(e, "appRingsEnabled") ?? d.AppRingsEnabled,
            ShowSlotNumbers = TryBool(e, "showSlotNumbers") ?? d.ShowSlotNumbers,
            ShowConfirmations = TryBool(e, "showConfirmations") ?? d.ShowConfirmations,
            ClosesGaps = TryBool(e, "closesGaps") ?? d.ClosesGaps,
            ChecksForUpdates = TryBool(e, "checksForUpdates") ?? d.ChecksForUpdates,
            HasCompletedOnboarding = TryBool(e, "hasCompletedOnboarding") ?? d.HasCompletedOnboarding,
        };
    }

    public static AppProfile Profile(JsonElement e)
    {
        RequireObject(e, "app ring");
        var bundleId = RequiredString(e, "bundleID");
        return new AppProfile(
            Try(e, "id", v => (Guid?)v.GetGuid()) ?? Guid.NewGuid(),
            bundleId,
            Try(e, "appName", v => v.GetString()) ?? bundleId,
            TryBool(e, "isEnabled") ?? true,
            Try(e, "ring", Ring) ?? new Ring(),
            TryBool(e, "inheritsGlobalSlots") ?? false);
    }

    public static Ring Ring(JsonElement e)
    {
        RequireObject(e, "ring");
        var slots = Required(e, "slots");
        if (slots.ValueKind != JsonValueKind.Array) throw new JsonException("A ring's slots must be an array.");
        return new Ring(slots.EnumerateArray().Select(Slot));
    }

    /// <summary>Tolerant: an action, icon, title or tint that fails to decode (e.g. from a newer
    /// version) leaves that part empty instead of failing the whole config.</summary>
    public static Slot Slot(JsonElement e)
    {
        RequireObject(e, "slot");
        return new Slot(
            Try(e, "id", v => (Guid?)v.GetGuid()) ?? Guid.NewGuid(),
            Try(e, "action", Action),
            Try(e, "title", v => v.GetString()),
            Try(e, "icon", Icon),
            Try(e, "tint", Color));
    }

    public static HaloAction Action(JsonElement e)
    {
        RequireObject(e, "action");
        var kind = EnumNames.Parse<ActionKind>(RequiredString(e, "type"));
        var v = Required(e, "value");
        return kind switch
        {
            ActionKind.App => new AppAction(new AppTarget(
                RequiredString(v, "bundleID"),
                RequiredString(v, "name"),
                OptionalString(v, "path"),
                OptionalEnum(v, "behavior", AppBehavior.Open))),
            ActionKind.Url => new UrlAction(new WebLink(RequiredString(v, "url"), OptionalString(v, "openWithBundleID"))),
            ActionKind.File => new FileAction(new FileTarget(RequiredString(v, "path"), OptionalBool(v, "revealInFinder") ?? false)),
            ActionKind.Keystroke => new KeystrokeAction(KeyCombo(v)),
            ActionKind.Media => new MediaAction(EnumValue<MediaCommand>(v)),
            ActionKind.Screenshot => new ScreenshotAction(new ScreenshotOptions(
                EnumNames.Parse<ScreenshotMode>(RequiredString(v, "mode")),
                OptionalBool(v, "toClipboard") ?? false)),
            ActionKind.System => new SystemAction(EnumValue<SystemCommand>(v)),
            ActionKind.Edit => new EditAction(EnumValue<EditCommand>(v)),
            ActionKind.Window => new WindowAction(EnumValue<WindowCommand>(v)),
            ActionKind.Shortcut => new ShortcutAction(new ShortcutRef(RequiredString(v, "name"), OptionalBool(v, "passSelection") ?? false)),
            ActionKind.AppShortcut => new AppShortcutAction(new AppShortcut(
                RequiredString(v, "bundleID"),
                RequiredString(v, "appName"),
                RequiredString(v, "title"),
                KeyCombo(Required(v, "combo")),
                OptionalString(v, "symbol"),
                OptionalEnum(v, "delivery", AppDelivery.BringToFront))),
            ActionKind.MenuItem => new MenuItemAction(new MenuItemRef(
                RequiredString(v, "bundleID"),
                RequiredString(v, "appName"),
                Required(v, "path") is { ValueKind: JsonValueKind.Array } path
                    ? path.EnumerateArray().Select(t => t.GetString() ?? throw new JsonException("Menu titles must be strings.")).ToArray()
                    : throw new JsonException("\"path\" must be an array."),
                OptionalEnum(v, "delivery", AppDelivery.BringToFront))),
            ActionKind.AppleScript => new AppleScriptAction(Script(v)),
            ActionKind.Shell => new ShellAction(Script(v)),
            ActionKind.Text => new TextAction(new TextSnippet(
                RequiredString(v, "text"),
                OptionalEnum(v, "method", TextMethod.Paste),
                OptionalBool(v, "pressReturn") ?? false)),
            ActionKind.AiPrompt => new AiPromptAction(new AiPrompt(
                EnumNames.Parse<AiService>(RequiredString(v, "service")),
                RequiredString(v, "template"),
                OptionalString(v, "customURLTemplate"))),
            ActionKind.Folder => new FolderAction(Ring(v)),
            ActionKind.Macro => new MacroAction(Macro(v)),
            _ => throw new JsonException($"Unhandled action kind {kind}."),
        };
    }

    public static KeyCombo KeyCombo(JsonElement e)
    {
        RequireObject(e, "key combo");
        return new KeyCombo(
            Required(e, "keyCode").GetUInt16(),
            (Modifiers)Required(e, "modifiers").GetByte(),
            RequiredString(e, "keyLabel"));
    }

    /// <summary>Swift's enum encoding: exactly one key naming the case.</summary>
    public static IconSpec Icon(JsonElement e)
    {
        var (name, payload) = SingleCase(e, "icon");
        return name switch
        {
            "symbol" => new SymbolIcon(RequiredString(payload, "name")),
            "app" => new AppIcon(RequiredString(payload, "bundleID")),
            "image" => new ImageIcon(Required(payload, "png").GetBytesFromBase64()),
            "emoji" => new EmojiIcon(RequiredString(payload, "_0")),
            _ => throw new JsonException($"Unknown icon \"{name}\"."),
        };
    }

    public static RingColor Color(JsonElement e)
    {
        var (name, payload) = SingleCase(e, "colour");
        return name switch
        {
            "preset" => RingColor.FromPreset(EnumNames.Parse<RingColorPreset>(RequiredString(payload, "_0"))),
            "custom" => RingColor.FromRgb(
                Required(payload, "red").GetDouble(),
                Required(payload, "green").GetDouble(),
                Required(payload, "blue").GetDouble()),
            _ => throw new JsonException($"Unknown colour \"{name}\"."),
        };
    }

    /// <summary>Exceptions that mean "this JSON doesn't have the expected shape".</summary>
    public static bool IsDecodeError(Exception e) =>
        e is JsonException or InvalidOperationException or FormatException or OverflowException or KeyNotFoundException;

    private static Macro Macro(JsonElement e)
    {
        RequireObject(e, "smart action");
        if (!TryGet(e, "steps", out var steps)) return new Macro();
        if (steps.ValueKind != JsonValueKind.Array) throw new JsonException("Smart Action steps must be an array.");
        return new Macro(steps.EnumerateArray().Select(s =>
        {
            RequireObject(s, "step");
            return new MacroStep(
                Try(s, "id", v => (Guid?)v.GetGuid()) ?? Guid.NewGuid(),
                Action(Required(s, "action")),
                TryDouble(s, "delayAfter") ?? 0.15);
        }).ToArray());
    }

    private static ScriptSource Script(JsonElement e) => new(RequiredString(e, "source"), OptionalString(e, "shell"));

    private static (string Name, JsonElement Payload) SingleCase(JsonElement e, string what)
    {
        RequireObject(e, what);
        var properties = e.EnumerateObject().ToArray();
        if (properties.Length != 1) throw new JsonException($"An {what} must have exactly one case.");
        return (properties[0].Name, properties[0].Value);
    }

    private static T EnumValue<T>(JsonElement e) where T : struct, Enum =>
        e.ValueKind == JsonValueKind.String
            ? EnumNames.Parse<T>(e.GetString()!)
            : throw new JsonException($"Expected a {typeof(T).Name} name.");

    // MARK: Required and optional values (strict: a present value of the wrong type throws)

    private static void RequireObject(JsonElement e, string what)
    {
        if (e.ValueKind != JsonValueKind.Object) throw new JsonException($"Expected {what} to be an object.");
    }

    private static JsonElement Required(JsonElement e, string key) =>
        TryGet(e, key, out var value) ? value : throw new JsonException($"Missing \"{key}\".");

    private static string RequiredString(JsonElement e, string key) =>
        Required(e, key) is { ValueKind: JsonValueKind.String } s ? s.GetString()! : throw new JsonException($"\"{key}\" must be a string.");

    private static string? OptionalString(JsonElement e, string key) =>
        TryGet(e, key, out var value) ? (value.ValueKind == JsonValueKind.String ? value.GetString() : throw new JsonException($"\"{key}\" must be a string.")) : null;

    private static bool? OptionalBool(JsonElement e, string key) => TryGet(e, key, out var value) ? value.GetBoolean() : null;

    private static T OptionalEnum<T>(JsonElement e, string key, T fallback) where T : struct, Enum =>
        TryGet(e, key, out var value) ? EnumValue<T>(value) : fallback;

    /// <summary>The property's value, or false when it is absent or null (Swift's <c>decodeIfPresent</c>).</summary>
    private static bool TryGet(JsonElement e, string key, out JsonElement value) =>
        e.TryGetProperty(key, out value) && value.ValueKind != JsonValueKind.Null;

    // MARK: Tolerant values (anything unreadable becomes null; Swift's `try?`)

    private static T? Try<T>(JsonElement e, string key, Func<JsonElement, T?> read) =>
        TryGet(e, key, out var value) ? Attempt(() => read(value)) : default;

    private static double? TryDouble(JsonElement e, string key) => Try(e, key, v => (double?)v.GetDouble());

    private static bool? TryBool(JsonElement e, string key) => Try(e, key, v => (bool?)v.GetBoolean());

    private static T TryEnum<T>(JsonElement e, string key, T fallback) where T : struct, Enum =>
        Try(e, key, v => (T?)EnumValue<T>(v)) ?? fallback;

    private static T? Attempt<T>(Func<T?> read)
    {
        try
        {
            return read();
        }
        catch (Exception ex) when (IsDecodeError(ex))
        {
            return default;
        }
    }
}
