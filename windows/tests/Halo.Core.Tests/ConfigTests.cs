using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Halo.Core.Catalog;
using Halo.Core.Serialization;
using Halo.Core.Storage;

namespace Halo.Core.Tests;

public class ConfigTests
{
    private static byte[] Utf8(string s) => Encoding.UTF8.GetBytes(s);

    [Fact(DisplayName = "Default config round-trips through JSON")]
    public void RoundTrip()
    {
        var config = HaloConfig.Default with
        {
            AppProfiles = [new AppProfile("chrome.exe", "Google Chrome", DefaultRings.Media())],
            Settings = new AppSettings { Trigger = null },
        };
        var decoded = HaloJson.Decode(HaloJson.Encode(config));
        Assert.Equal(config, decoded);
        Assert.Null(decoded.Settings.Trigger);
    }

    [Fact(DisplayName = "Every action kind round-trips")]
    public void EveryAction()
    {
        HaloAction[] actions =
        [
            new AppAction(new AppTarget("chrome.exe", "Chrome", @"C:\Program Files\Google\Chrome\Application\chrome.exe", AppBehavior.Toggle)),
            new UrlAction(new WebLink("https://example.com", "msedge.exe")),
            new FileAction(new FileTarget("~/Downloads", Reveal: true)),
            new KeystrokeAction(new KeyCombo(VirtualKeys.T, Modifiers.Control | Modifiers.Shift, "T")),
            new MediaAction(MediaCommand.VolumeUp),
            new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Window, true)),
            new SystemAction(SystemCommand.LockScreen),
            new EditAction(EditCommand.Paste),
            new WindowAction(WindowCommand.LeftHalf),
            new ShortcutAction(new ShortcutRef("Morning", true)),
            new AppShortcutAction(new AppShortcut("ms-teams.exe", "Teams", "Mute", new KeyCombo(0x4D, Modifiers.Control | Modifiers.Shift, "M"), "mic.slash", AppDelivery.BringToFrontAndReturn)),
            new MenuItemAction(new MenuItemRef("com.apple.finder", "Finder", ["View", "Show Sidebar"])),
            new AppleScriptAction(new ScriptSource("beep")),
            new ShellAction(new ScriptSource("Get-Date", "pwsh")),
            new TextAction(new TextSnippet("Hello {date}", TextMethod.Type, true)),
            new AiPromptAction(new AiPrompt(AiService.Custom, "Explain {selection}", "https://x.test/?q={prompt}")),
            new FolderAction(DefaultRings.Windows()),
            new MacroAction(new Macro([new MacroStep(new EditAction(EditCommand.Copy)), new MacroStep(new MediaAction(MediaCommand.Mute), 0.5)])),
        ];
        Assert.Equal(Enum.GetValues<ActionKind>().ToHashSet(), actions.Select(a => a.Kind).ToHashSet());
        foreach (var action in actions)
        {
            Assert.Equal(action, HaloJson.DecodeAction(HaloJson.EncodeAction(action)));
        }
    }

    [Fact(DisplayName = "An unknown action type empties that slot instead of failing the config")]
    public void TolerantSlots()
    {
        const string json = """
        {"globalRing":{"slots":[
          {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","action":{"type":"teleport","value":{}}},
          {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","action":{"type":"media","value":"mute"}}
        ]}}
        """;
        var config = HaloJson.Decode(Utf8(json));
        Assert.Equal(Ring.MinSlotCount, config.GlobalRing.SlotCount);   // padded to the minimum
        Assert.Null(config.GlobalRing[0].Action);
        Assert.Equal(new MediaAction(MediaCommand.Mute), config.GlobalRing[1].Action);
        Assert.Equal(new AppSettings(), config.Settings);
    }

    [Fact(DisplayName = "Missing settings keys fall back to defaults; explicit null clears the trigger")]
    public void TolerantSettings()
    {
        var partial = HaloJson.DecodeSettings(Utf8("""{"theme":"glass","ringScale":9,"holdThreshold":"slow"}"""));
        Assert.Equal(RingTheme.Glass, partial.Theme);
        Assert.Equal(AppSettings.RingScaleRange.Max, partial.RingScale);
        Assert.Equal(0.28, partial.HoldThreshold);
        Assert.Equal(KeyCombo.DefaultTrigger, partial.Trigger);
        var cleared = HaloJson.DecodeSettings(Utf8("""{"trigger":null}"""));
        Assert.Null(cleared.Trigger);
    }

    [Fact(DisplayName = "Default trigger is Ctrl+Shift+Alt+H")]
    public void DefaultTrigger()
    {
        Assert.Equal("Ctrl+Shift+Alt+H", KeyCombo.DefaultTrigger.DisplayString);
        Assert.Equal(0x48, KeyCombo.DefaultTrigger.KeyCode);
        Assert.Equal(KeyCombo.DefaultTrigger, new AppSettings().Trigger);
    }

    [Fact(DisplayName = "Ring resizing keeps filled slots")]
    public void Resize()
    {
        var ring = new Ring([new Slot(new MediaAction(MediaCommand.Mute)), new Slot(), new Slot(new EditAction(EditCommand.Copy)), new Slot(), new Slot(), new Slot()]);
        ring = ring.Resized(4);
        Assert.Equal(4, ring.SlotCount);
        Assert.Equal(2, ring.FilledCount);
        ring = ring.Resized(40);
        Assert.Equal(Ring.MaxSlotCount, ring.SlotCount);
        ring = ring.Resized(1);
        Assert.Equal(Ring.MinSlotCount, ring.SlotCount);
    }

    [Fact(DisplayName = "Compacting keeps filled slots in order and maps them back")]
    public void Compacting()
    {
        var ring = new Ring(8)
            .WithSlot(1, new Slot(new MediaAction(MediaCommand.Mute)))
            .WithSlot(4, new Slot(new EditAction(EditCommand.Copy)))
            .WithSlot(6, new Slot(new SystemAction(SystemCommand.LockScreen)));
        var compact = ring.Compacted();
        Assert.Equal(3, compact.Ring.SlotCount);
        Assert.Equal([1, 4, 6], compact.SourceIndices);
        Assert.Equal(new EditAction(EditCommand.Copy), compact.Ring[1].Action);
        Assert.Equal(0, new Geometry.RingGeometry(3).SlotAt(0, -100, 10));

        Assert.Equal(Enumerable.Range(0, 6), DefaultRings.Media().Compacted().SourceIndices);
        Assert.Equal(5, new Ring(5).Compacted().Ring.SlotCount);
    }

    [Fact(DisplayName = "New settings default on and round-trip")]
    public void NewSettings()
    {
        var defaults = new AppSettings();
        Assert.True(defaults.ClosesGaps);
        Assert.True(defaults.ChecksForUpdates);
        var off = defaults with { ClosesGaps = false, ChecksForUpdates = false };
        Assert.Equal(off, HaloJson.DecodeSettings(HaloJson.EncodeSettings(off)));
        Assert.True(HaloJson.DecodeSettings(Utf8("{}")).ClosesGaps);
    }

    [Fact(DisplayName = "Swap, move and clear keep slots in place")]
    public void Reorder()
    {
        var ring = DefaultRings.Media();
        var swapped = ring.Swapped(0, 1);
        Assert.Equal(ring[0], swapped[1]);
        var moved = ring.Moved(0, 5);
        Assert.Equal(ring[0], moved[5]);
        Assert.Equal(ring[1], moved[0]);
        Assert.True(ring.Cleared(2)[2].IsEmpty);
        Assert.Same(ring, ring.Swapped(0, 99));
    }

    [Fact(DisplayName = "Duplicate slot ids are regenerated")]
    public void DuplicateIds()
    {
        var slot = new Slot(new MediaAction(MediaCommand.Mute));
        var ring = new Ring([slot, slot, slot, slot]);
        Assert.Equal(4, ring.Slots.Select(s => s.Id).Distinct().Count());
    }

    [Fact(DisplayName = "Folder paths read and update nested rings")]
    public void FolderPaths()
    {
        var ring = DefaultRings.Global();
        var folderIndex = ring.Slots.ToList().FindIndex(s => s.Action?.IsFolder == true);
        Assert.Equal(6, ring.RingAt([folderIndex])?.SlotCount);
        Assert.Null(ring.RingAt([0]));
        var updated = ring.UpdatingRing([folderIndex], r => r.Cleared(0));
        Assert.NotNull(updated);
        Assert.Null(updated.RingAt([folderIndex])![0].Action);
        Assert.Null(ring.UpdatingRing([0], r => r));
    }

    [Fact(DisplayName = "App rings resolve, inherit empty slots, and respect the switch")]
    public void Resolution()
    {
        var appRing = new Ring(8).WithSlot(0, new Slot(new EditAction(EditCommand.Copy)));
        var config = HaloConfig.Default with
        {
            AppProfiles = [new AppProfile("Example.exe", "Example", appRing, inheritsGlobalSlots: true)],
        };

        var resolved = config.ResolveRing("example.EXE");
        Assert.Equal("Example.exe", resolved.Profile?.BundleId);
        Assert.Equal(new EditAction(EditCommand.Copy), resolved.Ring[0].Action);
        Assert.Equal(config.GlobalRing[1].Action, resolved.Ring[1].Action);
        Assert.Equal(resolved.Ring.SlotCount, resolved.Ring.Slots.Select(s => s.Id).Distinct().Count());

        Assert.Null(config.ResolveRing("other.exe").Profile);
        Assert.NotNull(config.ResolveRing(["Microsoft.App_123!App", "example.exe"]).Profile);
        Assert.Null((config with { Settings = config.Settings with { AppRingsEnabled = false } }).ResolveRing("example.exe").Profile);
    }

    [Fact(DisplayName = "Save rotates a backup and load recovers from a corrupt file")]
    public void Disk()
    {
        var dir = Path.Combine(Path.GetTempPath(), "halo-tests-" + Guid.NewGuid());
        try
        {
            var path = Path.Combine(dir, "config.json");
            Assert.IsType<ConfigLoadOutcome.CreatedDefault>(ConfigFile.Load(path).Outcome);
            var config = HaloConfig.Default;
            ConfigFile.Save(config, path);
            config = config with { Settings = config.Settings with { Theme = RingTheme.Glass } };
            ConfigFile.Save(config, path);
            Assert.True(File.Exists(ConfigFile.BackupPath(path)));
            Assert.Equal(RingTheme.Glass, ConfigFile.Load(path).Config.Settings.Theme);

            File.WriteAllText(path, "{ not json");
            var (recovered, outcome) = ConfigFile.Load(path);
            var aside = Assert.IsType<ConfigLoadOutcome.RecoveredFromCorruption>(outcome);
            Assert.True(File.Exists(aside.MovedTo));
            Assert.Equal(RingTheme.Classic, recovered.Settings.Theme);   // the backup is one edit behind
        }
        finally
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
        }
    }

    [Fact(DisplayName = "Import rejects files that aren't Halo configs")]
    public void Import()
    {
        Assert.Throws<ConfigImportException>(() => ConfigFile.Import(Utf8("""{"hello":"world"}""")));
        Assert.Equal(HaloConfig.Default.GlobalRing.SlotCount, ConfigFile.Import(ConfigFile.Export(HaloConfig.Default)).GlobalRing.SlotCount);
    }

    [Fact(DisplayName = "An unreadable app ring is skipped, the others kept")]
    public void TolerantProfiles()
    {
        const string json = """
        {"globalRing":{"slots":[]},"appProfiles":[
          {"appName":"Broken"},
          {"bundleID":"code.exe","appName":"Code","ring":{"slots":[]}}
        ]}
        """;
        var config = HaloJson.Decode(Utf8(json));
        Assert.Single(config.AppProfiles);
        Assert.Equal("code.exe", config.AppProfiles[0].BundleId);
        Assert.True(config.AppProfiles[0].IsEnabled);
    }

    /// <summary>A config in the exact shape the macOS app writes (Swift <c>JSONEncoder</c>,
    /// pretty-printed with sorted keys), including Mac-only actions and every icon/colour case.</summary>
    private const string MacConfig = """
    {
      "appProfiles" : [
        {
          "appName" : "Safari",
          "bundleID" : "com.apple.Safari",
          "id" : "3B1E6F7A-0C4D-4B8E-9C2F-1A2B3C4D5E6F",
          "inheritsGlobalSlots" : true,
          "isEnabled" : false,
          "ring" : {
            "slots" : [
              { "id" : "11111111-2222-3333-4444-555555555555" },
              { "id" : "11111111-2222-3333-4444-555555555556" },
              { "id" : "11111111-2222-3333-4444-555555555557" },
              { "id" : "11111111-2222-3333-4444-555555555558" }
            ]
          }
        }
      ],
      "globalRing" : {
        "slots" : [
          {
            "action" : { "type" : "media", "value" : "playPause" },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "tint" : { "preset" : { "_0" : "mint" } }
          },
          {
            "action" : {
              "type" : "app",
              "value" : { "behavior" : "toggle", "bundleID" : "com.apple.finder", "name" : "Finder", "path" : "/System/Library/CoreServices/Finder.app" }
            },
            "icon" : { "app" : { "bundleID" : "com.apple.finder" } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96500",
            "title" : "Files"
          },
          {
            "action" : { "type" : "appleScript", "value" : { "source" : "beep" } },
            "icon" : { "emoji" : { "_0" : "🔔" } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96501",
            "tint" : { "custom" : { "blue" : 0.25, "green" : 0.5, "red" : 1 } }
          },
          {
            "action" : {
              "type" : "aiPrompt",
              "value" : { "service" : "chatGPT", "template" : "Explain:\n\n{selection}" }
            },
            "icon" : { "symbol" : { "name" : "sparkles" } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96502"
          },
          {
            "action" : {
              "type" : "macro",
              "value" : {
                "steps" : [
                  {
                    "action" : { "type" : "keystroke", "value" : { "keyCode" : 45, "keyLabel" : "N", "modifiers" : 8 } },
                    "delayAfter" : 0.6,
                    "id" : "6F9619FF-8B86-D011-B42D-00C04FC96503"
                  }
                ]
              }
            },
            "icon" : { "image" : { "png" : "iVBORw0KGgo=" } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96504"
          },
          {
            "action" : { "type" : "folder", "value" : { "slots" : [
              { "action" : { "type" : "window", "value" : "leftHalf" }, "id" : "6F9619FF-8B86-D011-B42D-00C04FC96505" },
              { "action" : { "type" : "screenshot", "value" : { "mode" : "fullScreen", "toClipboard" : true } }, "id" : "6F9619FF-8B86-D011-B42D-00C04FC96506" },
              { "action" : { "type" : "shortcut", "value" : { "name" : "Morning", "passSelection" : false } }, "id" : "6F9619FF-8B86-D011-B42D-00C04FC96507" },
              { "action" : { "type" : "text", "value" : { "method" : "type", "pressReturn" : true, "text" : "Hi {date}" } }, "id" : "6F9619FF-8B86-D011-B42D-00C04FC96508" },
              {
                "action" : {
                  "type" : "appShortcut",
                  "value" : {
                    "appName" : "Zoom", "bundleID" : "us.zoom.xos",
                    "combo" : { "keyCode" : 0, "keyLabel" : "A", "modifiers" : 12 },
                    "delivery" : "bringToFrontAndReturn", "symbol" : "mic.slash", "title" : "Mute"
                  }
                },
                "id" : "6F9619FF-8B86-D011-B42D-00C04FC96512"
              },
              {
                "action" : {
                  "type" : "menuItem",
                  "value" : { "appName" : "Finder", "bundleID" : "com.apple.finder", "delivery" : "bringToFront", "path" : [ "View", "Show Sidebar" ] }
                },
                "id" : "6F9619FF-8B86-D011-B42D-00C04FC96513"
              }
            ] } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96509",
            "title" : "More"
          },
          {
            "action" : { "type" : "file", "value" : { "path" : "~/Downloads", "revealInFinder" : false } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96510"
          },
          {
            "action" : { "type" : "url", "value" : { "openWithBundleID" : "com.apple.Safari", "url" : "https://example.com/a/b" } },
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC96511"
          }
        ]
      },
      "schemaVersion" : 1,
      "settings" : {
        "accent" : { "preset" : { "_0" : "blue" } },
        "animationSpeed" : 1.5,
        "appRingsEnabled" : true,
        "checksForUpdates" : false,
        "closesGaps" : true,
        "hapticsEnabled" : true,
        "hasCompletedOnboarding" : true,
        "holdThreshold" : 0.28,
        "labelMode" : "always",
        "launchAtLogin" : false,
        "placement" : "screenCenter",
        "ringScale" : 1.2,
        "selectionMode" : "holdAndRelease",
        "showConfirmations" : true,
        "showMenuBarIcon" : true,
        "showSlotNumbers" : false,
        "soundsEnabled" : false,
        "theme" : "glass",
        "trigger" : { "keyCode" : 4, "keyLabel" : "H", "modifiers" : 13 }
      }
    }
    """;

    [Fact(DisplayName = "A config written by the Mac app decodes fully and re-encodes to the same JSON")]
    public void MacShape()
    {
        var config = HaloJson.Decode(Utf8(MacConfig));
        Assert.Equal(SelectionMode.HoldAndRelease, config.Settings.SelectionMode);
        Assert.Equal(RingPlacement.ScreenCenter, config.Settings.Placement);
        Assert.Equal(new KeyCombo(4, Modifiers.Control | Modifiers.Shift | Modifiers.Command, "H"), config.Settings.Trigger);
        Assert.All(config.GlobalRing.Slots, slot => Assert.NotNull(slot.Action));
        Assert.Equal(new AppleScriptAction(new ScriptSource("beep")), config.GlobalRing[2].Action);
        Assert.Equal(new EmojiIcon("🔔"), config.GlobalRing[2].Icon);
        Assert.Equal(RingColor.FromRgb(1, 0.5, 0.25), config.GlobalRing[2].Tint);
        Assert.Equal(AiService.ChatGpt, Assert.IsType<AiPromptAction>(config.GlobalRing[3].Action).Prompt.Service);
        Assert.False(config.AppProfiles[0].IsEnabled);
        Assert.False(config.Settings.ChecksForUpdates);
        var folder = Assert.IsType<FolderAction>(config.GlobalRing[5].Action).Ring;
        Assert.Equal(AppDelivery.BringToFrontAndReturn, Assert.IsType<AppShortcutAction>(folder[4].Action).Shortcut.Delivery);
        Assert.Equal(["View", "Show Sidebar"], Assert.IsType<MenuItemAction>(folder[5].Action).Item.Path);

        var original = JsonNode.Parse(MacConfig);
        var reencoded = JsonNode.Parse(HaloJson.Encode(config));
        Assert.True(JsonNode.DeepEquals(original, reencoded), reencoded!.ToJsonString());
    }

    [Fact(DisplayName = "Encoding sorts keys, upper-cases UUIDs and omits absent optionals")]
    public void EncodingConventions()
    {
        var id = Guid.Parse("6f9619ff-8b86-d011-b42d-00c04fc964ff");
        var ring = new Ring([new Slot(id, new UrlAction(new WebLink("https://a.test/x")))]);
        var json = Encoding.UTF8.GetString(HaloJson.EncodeRing(ring));
        Assert.Contains("6F9619FF-8B86-D011-B42D-00C04FC964FF", json, StringComparison.Ordinal);
        Assert.DoesNotContain("openWithBundleID", json, StringComparison.Ordinal);
        Assert.DoesNotContain("title", json, StringComparison.Ordinal);
        Assert.Contains("https://a.test/x", json, StringComparison.Ordinal);   // slashes unescaped

        var settings = JsonNode.Parse(HaloJson.EncodeSettings(new AppSettings()))!.AsObject();
        var keys = settings.Select(p => p.Key).ToArray();
        Assert.Equal(keys.Order(StringComparer.Ordinal), keys);
        Assert.Equal(19, keys.Length);
    }

    [Fact(DisplayName = "A Windows-only system command reads as an empty slot on an older reader, not an error")]
    public void UnknownEnumCase()
    {
        var json = """{"globalRing":{"slots":[{"action":{"type":"system","value":"holographicMode"}}]}}""";
        Assert.Null(HaloJson.Decode(Utf8(json)).GlobalRing[0].Action);
        Assert.Equal(new SystemAction(SystemCommand.QuickSettings),
            HaloJson.DecodeAction(Utf8("""{"type":"system","value":"quickSettings"}""")));
    }

    [Fact(DisplayName = "Non-JSON input fails with a JsonException")]
    public void NotJson()
    {
        Assert.ThrowsAny<JsonException>(() => HaloJson.Decode(Utf8("{ not json")));
        Assert.ThrowsAny<JsonException>(() => HaloJson.Decode(Utf8("""{"settings":{}}""")));
    }
}
