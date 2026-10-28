using System.Text.Json.Nodes;

namespace Halo.Core.Serialization;

/// <summary>Model → JSON nodes, mirroring the macOS app's <c>Encodable</c> conformances.</summary>
internal static class JsonWriters
{
    public static JsonObject Config(HaloConfig config) => new()
    {
        ["schemaVersion"] = HaloConfig.CurrentSchemaVersion,
        ["settings"] = Settings(config.Settings),
        ["globalRing"] = Ring(config.GlobalRing),
        ["appProfiles"] = Array(config.AppProfiles, Profile),
    };

    public static JsonObject Settings(AppSettings s) => new()
    {
        ["trigger"] = s.Trigger is null ? null : KeyCombo(s.Trigger),
        ["selectionMode"] = EnumNames.Name(s.SelectionMode),
        ["holdThreshold"] = s.HoldThreshold,
        ["theme"] = EnumNames.Name(s.Theme),
        ["ringScale"] = s.RingScale,
        ["labelMode"] = EnumNames.Name(s.LabelMode),
        ["placement"] = EnumNames.Name(s.Placement),
        ["animationSpeed"] = s.AnimationSpeed,
        ["accent"] = Color(s.Accent),
        ["hapticsEnabled"] = s.HapticsEnabled,
        ["soundsEnabled"] = s.SoundsEnabled,
        ["showMenuBarIcon"] = s.ShowMenuBarIcon,
        ["launchAtLogin"] = s.LaunchAtLogin,
        ["appRingsEnabled"] = s.AppRingsEnabled,
        ["showSlotNumbers"] = s.ShowSlotNumbers,
        ["showConfirmations"] = s.ShowConfirmations,
        ["closesGaps"] = s.ClosesGaps,
        ["checksForUpdates"] = s.ChecksForUpdates,
        ["hasCompletedOnboarding"] = s.HasCompletedOnboarding,
    };

    public static JsonObject Profile(AppProfile p) => new()
    {
        ["id"] = Uuid(p.Id),
        ["bundleID"] = p.BundleId,
        ["appName"] = p.AppName,
        ["isEnabled"] = p.IsEnabled,
        ["ring"] = Ring(p.Ring),
        ["inheritsGlobalSlots"] = p.InheritsGlobalSlots,
    };

    public static JsonObject Ring(Ring ring) => new() { ["slots"] = Array(ring.Slots, Slot) };

    public static JsonObject Slot(Slot slot)
    {
        var obj = new JsonObject { ["id"] = Uuid(slot.Id) };
        if (slot.Action is not null) obj["action"] = Action(slot.Action);
        if (slot.Title is not null) obj["title"] = slot.Title;
        if (slot.Icon is not null) obj["icon"] = Icon(slot.Icon);
        if (slot.Tint is not null) obj["tint"] = Color(slot.Tint);
        return obj;
    }

    public static JsonObject Action(HaloAction action) => new()
    {
        ["type"] = EnumNames.Name(action.Kind),
        ["value"] = action switch
        {
            AppAction a => App(a.Target),
            UrlAction u => Optional(new JsonObject { ["url"] = u.Link.Url }, "openWithBundleID", u.Link.OpenWithBundleId),
            FileAction f => new JsonObject { ["path"] = f.Target.Path, ["revealInFinder"] = f.Target.Reveal },
            KeystrokeAction k => KeyCombo(k.Combo),
            MediaAction m => EnumNames.Name(m.Command),
            ScreenshotAction s => new JsonObject { ["mode"] = EnumNames.Name(s.Options.Mode), ["toClipboard"] = s.Options.ToClipboard },
            SystemAction s => EnumNames.Name(s.Command),
            EditAction e => EnumNames.Name(e.Command),
            WindowAction w => EnumNames.Name(w.Command),
            ShortcutAction s => new JsonObject { ["name"] = s.Shortcut.Name, ["passSelection"] = s.Shortcut.PassSelection },
            AppShortcutAction a => Optional(new JsonObject
            {
                ["bundleID"] = a.Shortcut.BundleId,
                ["appName"] = a.Shortcut.AppName,
                ["title"] = a.Shortcut.Title,
                ["combo"] = KeyCombo(a.Shortcut.Combo),
                ["delivery"] = EnumNames.Name(a.Shortcut.Delivery),
            }, "symbol", a.Shortcut.Symbol),
            MenuItemAction m => new JsonObject
            {
                ["bundleID"] = m.Item.BundleId,
                ["appName"] = m.Item.AppName,
                ["path"] = new JsonArray(m.Item.Path.Select(t => (JsonNode)t).ToArray()),
                ["delivery"] = EnumNames.Name(m.Item.Delivery),
            },
            AppleScriptAction a => Script(a.Script),
            ShellAction s => Script(s.Script),
            TextAction t => new JsonObject
            {
                ["text"] = t.Snippet.Text,
                ["method"] = EnumNames.Name(t.Snippet.Method),
                ["pressReturn"] = t.Snippet.PressReturn,
            },
            AiPromptAction p => Optional(new JsonObject
            {
                ["service"] = EnumNames.Name(p.Prompt.Service),
                ["template"] = p.Prompt.Template,
            }, "customURLTemplate", p.Prompt.CustomUrlTemplate),
            FolderAction f => Ring(f.Ring),
            MacroAction m => new JsonObject { ["steps"] = Array(m.Macro.Steps, Step) },
            _ => throw new ArgumentOutOfRangeException(nameof(action), action.Kind, "Unhandled action kind."),
        },
    };

    public static JsonObject KeyCombo(KeyCombo combo) => new()
    {
        ["keyCode"] = combo.KeyCode,
        ["modifiers"] = (byte)combo.Modifiers,
        ["keyLabel"] = combo.KeyLabel,
    };

    public static JsonObject Icon(IconSpec icon) => icon switch
    {
        SymbolIcon s => Case("symbol", new JsonObject { ["name"] = s.Name }),
        AppIcon a => Case("app", new JsonObject { ["bundleID"] = a.BundleId }),
        ImageIcon i => Case("image", new JsonObject { ["png"] = Convert.ToBase64String(i.Png) }),
        EmojiIcon e => Case("emoji", new JsonObject { ["_0"] = e.Text }),
        _ => throw new ArgumentOutOfRangeException(nameof(icon)),
    };

    public static JsonObject Color(RingColor color) => color switch
    {
        PresetColor p => Case("preset", new JsonObject { ["_0"] = EnumNames.Name(p.Preset) }),
        CustomColor c => Case("custom", new JsonObject { ["red"] = c.Red, ["green"] = c.Green, ["blue"] = c.Blue }),
        _ => throw new ArgumentOutOfRangeException(nameof(color)),
    };

    private static JsonObject App(AppTarget t) => Optional(new JsonObject
    {
        ["bundleID"] = t.BundleId,
        ["name"] = t.Name,
        ["behavior"] = EnumNames.Name(t.Behavior),
    }, "path", t.Path);

    private static JsonObject Script(ScriptSource s) => Optional(new JsonObject { ["source"] = s.Source }, "shell", s.Shell);

    private static JsonObject Step(MacroStep step) => new()
    {
        ["id"] = Uuid(step.Id),
        ["action"] = Action(step.Action),
        ["delayAfter"] = step.DelayAfter,
    };

    /// <summary>Swift encodes UUIDs upper-case.</summary>
    private static string Uuid(Guid id) => id.ToString("D").ToUpperInvariant();

    /// <summary>Swift's encoding of an enum case with associated values: <c>{"case": {…}}</c>.</summary>
    private static JsonObject Case(string name, JsonObject payload) => new() { [name] = payload };

    private static JsonObject Optional(JsonObject obj, string key, string? value)
    {
        if (value is not null) obj[key] = value;
        return obj;
    }

    private static JsonArray Array<T>(IEnumerable<T> items, Func<T, JsonNode> write) => new(items.Select(write).ToArray());
}
