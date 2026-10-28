#!/usr/bin/env python3
"""Generates AppActionPresets+Data.swift and docs/app-actions.json from one table.

Usage, from the repository root:
  python3 docs/tools/gen-app-actions.py \
      macos/Sources/HaloCore/Catalog/AppActionPresets+Data.swift docs/app-actions.json /tmp/symbols.txt
(the third file lists the SF Symbols used, to check they exist).

Each action: (id, title, mac, windows, symbol, delivery, notes, swift, source, windowsSource)
  mac      -> (keyLabel, "mods") for a real combo, a plain string for something a ring
              can't send (hold keys, sequences), or None when the app documents nothing.
  delivery -> "R" (.bringToFrontAndReturn) or "F" (.bringToFront)
  swift    -> True to emit a Swift preset (needs a real mac combo)
"""
import json, sys

SWIFT_OUT, JSON_OUT, SYMBOLS_OUT = sys.argv[1], sys.argv[2], sys.argv[3]

MODS = {"ctrl": ("⌃", ".control"), "opt": ("⌥", ".option"), "shift": ("⇧", ".shift"), "cmd": ("⌘", ".command")}
ORDER = ["ctrl", "opt", "shift", "cmd"]

def mac_display(m):
    if m is None: return None
    if isinstance(m, str): return m
    label, mods = m
    ms = mods.split()
    for x in ms: assert x in MODS, x
    sym = "".join(MODS[k][0] for k in ORDER if k in ms)
    return sym + (label.upper() if len(label) == 1 else label)

def swift_combo(m):
    label, mods = m
    ms = mods.split()
    arr = ", ".join(MODS[k][1] for k in ORDER if k in ms)
    lab = label.replace("\\", "\\\\").replace('"', '\\"')
    return f'keys("{lab}", [{arr}])'

def A(id, title, mac, win, symbol=None, delivery="F", notes=None, swift=True, source=None, windowsSource=None):
    if mac is None or isinstance(mac, str): swift = False
    if swift: assert symbol, id
    return dict(id=id, title=title, mac=mac, win=win, symbol=symbol, delivery=delivery, notes=notes, swift=swift,
                source=source, windowsSource=windowsSource)

# ---------------------------------------------------------------- sources
TEAMS = "https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2"
TEAMS_CONTROLS = "https://support.microsoft.com/en-us/teams/meetings/use-meeting-controls-in-microsoft-teams"
TEAMS_LAYOUTS = "https://mc.merill.net/message/MC992216"
ZOOM = "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050"
MEET = "https://support.google.com/a/users/answer/9896256?hl=en&co=GENIE.Platform%3DDesktop"
MEET_COMMUNITY = "https://support.google.com/meet/thread/216476128/hotkeys-for-google-meets-reactions?hl=en"
SLACK = "https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts"
WEBEX = "https://help.webex.com/en-us/article/7wr87q/Webex-App-%7C-Keyboard-navigation-and-shortcuts"
FACETIME = "https://support.apple.com/guide/facetime/keyboard-shortcuts-fctma3b7b94b/mac"
DISCORD = "https://discord.com/blog/how-to-use-keyboard-shortcuts-on-discord-create-custom-keybinds"
OUTLOOK_MAC = "https://support.microsoft.com/en-us/accessibility/outlook/mac/keyboard-shortcuts-in-outlook-for-mac"
OUTLOOK_WIN = "https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-outlook-3cdeb221-7ae5-4c1d-8c1d-9e63216c1efd"
WORD = "https://support.microsoft.com/en-us/accessibility/word/keyboard-shortcuts-in-word"
OFFICE_MAC = "https://support.microsoft.com/en-us/office/common-office-for-mac-keyboard-shortcuts-307f469a-1a05-4263-9b55-49df19a8b8ff"
EXCEL = "https://support.microsoft.com/en-us/accessibility/excel/keyboard-shortcuts-in-excel"
PPT_CREATE = "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-create-powerpoint-presentations"
PPT_SHOW = "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-deliver-powerpoint-presentations"
KEYNOTE = "https://support.apple.com/guide/keynote/keyboard-shortcuts-tanfde4a3e6d/mac"
NOTION = "https://www.notion.com/help/keyboard-shortcuts"
FIGMA_KEYBOARD = "https://help.figma.com/hc/en-us/articles/360040328653-Use-Figma-products-with-a-keyboard"
FIGMA_ACTIONS = "https://help.figma.com/hc/en-us/articles/23570416033943-Use-the-actions-menu-in-Figma-Design"
FIGMA_COMPONENTS = "https://help.figma.com/hc/en-us/articles/360038663154-Create-components-to-reuse-in-designs"
FIGMA_FRAMES = "https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design"
FIGMA_AUTOLAYOUT = "https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout-in-Figma"
FIGMA_EXPORT = "https://help.figma.com/hc/en-us/articles/360040028114-Export-static-designs-from-Figma"
PS = "https://helpx.adobe.com/content/dam/help/en/photoshop/using/default-keyboard-shortcuts/photoshop-keyboard-shortcuts.pdf"
LRC = "https://helpx.adobe.com/lightroom-classic/desktop/introduction-to-lightroom-classic/keyboard-shortcuts.html"
PR = "https://helpx.adobe.com/premiere/desktop/get-started/keyboard-shortcuts/default-keyboard-shortcuts.html"
FCP = "https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac"
RESOLVE = "https://documents.blackmagicdesign.com/UserManuals/DaVinci-Resolve-15-Keyboard-Shortcuts.pdf"
VSCODE_MAC = "https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf"
VSCODE_WIN = "https://code.visualstudio.com/shortcuts/keyboard-shortcuts-windows.pdf"
XCODE_ARCHIVE = "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"
XCODE_WWDC = "https://developer.apple.com/videos/play/wwdc2024/10181/"
CHROME = "https://support.google.com/chrome/answer/157179?hl=en&co=GENIE.Platform%3DDesktop"
SAFARI = "https://support.apple.com/guide/safari/keyboard-shortcuts-and-gestures-cpsh003/mac"
ARC = "https://web.archive.org/web/20260725225600/https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts"
EDGE = "https://support.microsoft.com/en-us/edge/keyboard-shortcuts-in-microsoft-edge"
SPOTIFY = "https://support.spotify.com/us/article/keyboard-shortcuts/"
MUSIC = "https://support.apple.com/guide/music/keyboard-shortcuts-mus1019/mac"
MUSIC_WIN = "https://support.apple.com/guide/music-windows/keyboard-shortcuts-mus1019/windows"
FINDER = "https://support.apple.com/en-us/102650"
MAIL = "https://support.apple.com/guide/mail/keyboard-shortcuts-mlhlb94f262b/mac"
NOTES = "https://support.apple.com/guide/notes/keyboard-shortcuts-and-gestures-apd46c25187e/mac"

APPS = []
def app(key, name, bundle_ids, win_process, source, notes, actions, windowsSource=None):
    APPS.append(dict(key=key, name=name, ids=bundle_ids, win=win_process, source=source, notes=notes,
                     actions=actions, windowsSource=windowsSource))

# ================================================================ meeting apps
app("teams", "Microsoft Teams", ["com.microsoft.teams2", "com.microsoft.teams"], "ms-teams.exe", TEAMS,
    "com.microsoft.teams2 = new Teams, verified on this Mac (26276.505). com.microsoft.teams = classic Teams (not installed here; retired). "
    "Windows: ms-teams.exe is new Teams, Teams.exe was classic (process names not verified on a Windows PC). "
    "Shortcuts are the Mac app column; the Teams web app differs for some (e.g. accept video call). "
    "Microsoft documents editing shortcuts in the Teams desktop app (Ctrl+. opens the Keyboard shortcuts window) and, since mid-2025, "
    "choosing a meeting-app shortcut layout in that dialog (Message center MC992216); a changed layout or custom key breaks these defaults.",
    [
        A("teams.mute", "Mute / Unmute", ("M", "shift cmd"), "Ctrl+Shift+M", "mic.slash.fill", "R"),
        A("teams.camera", "Camera On / Off", ("O", "shift cmd"), "Ctrl+Shift+O", "video.slash.fill", "R",
          "Teams web on Windows has no shortcut for this."),
        A("teams.raiseHand", "Raise / Lower Hand", ("K", "shift cmd"), "Ctrl+Shift+K", "hand.raised.fill", "R"),
        A("teams.share", "Share Content", ("E", "shift cmd"), "Ctrl+Shift+E", "rectangle.on.rectangle", "F",
          "Toggles the share-content tray; you still pick what to share, so this stays in Teams."),
        A("teams.hangUp", "Hang Up", ("H", "shift cmd"), "Ctrl+Shift+H", "phone.down.fill", "R",
          "Documented as End audio call / End video call."),
        A("teams.captions", "Live Captions", ("A", "shift cmd"), None, "captions.bubble", "R",
          "Mac only. Microsoft lists the same ⇧⌘A for Accept audio call (incoming-call toast). No Windows shortcut is documented."),
        A("teams.acceptAudio", "Accept Audio Call", ("A", "shift cmd"), "Ctrl+Shift+S", "phone.fill", "R",
          "Same Mac keys as Live Captions; acts on the incoming-call notification."),
        A("teams.acceptVideo", "Accept Video Call", ("V", "shift cmd"), "Ctrl+Shift+A", "video.fill", "F",
          "Stays in Teams so you see the call. Teams web uses ⇧⌘A / Alt+Shift+A instead."),
        A("teams.decline", "Decline Call", ("D", "shift cmd"), "Ctrl+Shift+D", "phone.down.circle.fill", "R"),
        A("teams.admitLobby", "Admit from Lobby", ("Y", "shift cmd"), "Ctrl+Shift+Y", "person.badge.plus", "R",
          "Acts on the lobby notification."),
        A("teams.speaker", "Toggle Speaker", None, "Ctrl+Shift+U", notes="Windows only; no Mac shortcut documented."),
        A("teams.temporaryUnmute", "Temporarily Unmute (hold)", "⌥Space (hold)", "Ctrl+Space (hold)",
          notes="Push-to-talk: must be held, so a ring tap can't do it. Needs Settings > Privacy > Keyboard shortcut to unmute turned on."),
        A("teams.meetingChat", "Open Meeting Chat (from notification)", "⌃⌘C", "Ctrl+Shift+R",
          notes="Only from the meeting-start notification; Teams documents no shortcut to open chat inside a running meeting."),
        A("teams.reactions", "Reactions (Like, Love, Applause, Laugh, Surprise)", None, None,
          notes="No default shortcut exists for meeting reactions on any platform. The shortcuts page has none, and the meeting-controls page only describes the React menu.",
          source=TEAMS_CONTROLS),
        A("teams.backgroundBlur", "Background Blur / Effects", None, None,
          notes="Not in Microsoft's current shortcut list (More > Apply background effects only). Ctrl+Shift+P / ⇧⌘P is quoted by third-party sites from classic Teams and is not documented by Microsoft, so it's left out.",
          source=TEAMS_CONTROLS),
        A("teams.shortcutsWindow", "Show / Edit Keyboard Shortcuts", "⌘.", "Ctrl+. (or Alt+/)",
          notes="Also where you set custom keys or pick a meeting-app layout (MC992216)."),
    ])

app("zoom", "Zoom Workplace", ["us.zoom.xos"], "Zoom.exe", ZOOM,
    "Bundle ID verified on this Mac (7.2.2). Shortcuts can be edited in Settings > Keyboard shortcuts. Many can be made global "
    "(work while Zoom isn't in front) by ticking the box next to them there; with the global box ticked Halo's bring-forward step isn't needed. "
    "Press-and-hold Space to temporarily unmute is a separate setting. Windows Alt+S / Alt+T need the meeting toolbar to have focus.",
    [
        A("zoom.mute", "Mute / Unmute", ("A", "shift cmd"), "Alt+A", "mic.slash.fill", "R"),
        A("zoom.camera", "Camera On / Off", ("V", "shift cmd"), "Alt+V", "video.slash.fill", "R"),
        A("zoom.raiseHand", "Raise / Lower Hand", ("Y", "opt"), "Alt+Y", "hand.raised.fill", "R"),
        A("zoom.share", "Start / Stop Share", ("S", "shift cmd"), "Alt+S", "rectangle.on.rectangle", "F",
          "Opens the share picker when starting, so this stays in Zoom. Windows needs the meeting toolbar focused."),
        A("zoom.chat", "Show / Hide Chat", ("H", "shift cmd"), "Alt+H", "message", "F"),
        A("zoom.participants", "Show / Hide Participants", ("U", "cmd"), "Alt+U", "person.2", "F"),
        A("zoom.reactionsPanel", "Reactions Panel", ("Y", "shift cmd"), "Ctrl+Shift+Y", "face.smiling", "F"),
        A("zoom.thumbsUp", "React: Thumbs Up", ("5", "opt cmd"), "Alt+Shift+5", "hand.thumbsup.fill", "R"),
        A("zoom.clap", "React: Clap", ("4", "opt cmd"), "Alt+Shift+4", "hands.clap.fill", "R"),
        A("zoom.heart", "React: Heart", ("6", "opt cmd"), "Alt+Shift+6", "heart.fill", "R", swift=False),
        A("zoom.joy", "React: Joy", ("7", "opt cmd"), "Alt+Shift+7", "face.smiling", "R", swift=False),
        A("zoom.wow", "React: Wow (Open Mouth)", ("8", "opt cmd"), "Alt+Shift+8", "face.smiling", "R", swift=False),
        A("zoom.tada", "React: Celebrate (Tada)", ("9", "opt cmd"), "Alt+Shift+9", "face.smiling", "R", swift=False),
        A("zoom.leave", "Leave Meeting", ("W", "cmd"), "Alt+Q", "phone.down.fill", "F",
          "Windows: 'Display prompt to end or leave meeting'. Mac has no dedicated entry; Zoom lists ⌘W as 'Close the current window', "
          "which in the meeting window brings up the leave prompt (inferred). Either way you confirm in Zoom."),
        A("zoom.answerCall", "Answer Call (Zoom Phone)", ("A", "ctrl shift"), "Ctrl+Shift+A", "phone.fill", "F",
          "Zoom Phone incoming calls, not meeting invites."),
        A("zoom.declineCall", "Decline Call (Zoom Phone)", ("D", "ctrl shift"), "Ctrl+Shift+D", "phone.down.circle.fill", "R"),
        A("zoom.record", "Start / Stop Local Recording", ("R", "shift cmd"), "Alt+R", "record.circle", "R", swift=False),
        A("zoom.pauseShare", "Pause / Resume Share", ("T", "shift cmd"), "Alt+T", "pause.rectangle", "R", swift=False),
        A("zoom.fullScreen", "Enter / Exit Full Screen", ("F", "shift cmd"), "Alt+F", "arrow.up.left.and.arrow.down.right", "F", swift=False),
        A("zoom.captions", "Captions", None, None, notes="Zoom's shortcut list has no captions shortcut."),
        A("zoom.backgroundBlur", "Background Blur", None, None, notes="No shortcut documented."),
        A("zoom.pushToTalk", "Push to Talk (hold Space)", "Space (hold)", "Space (hold)",
          notes="Must be held and needs the 'Press and hold SPACE key to temporarily unmute yourself' setting; a ring tap can't do it."),
    ])

app("meet", "Google Meet", ["com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan", "com.google.Chrome", "com.apple.Safari",
                            "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox"],
    None, MEET,
    "Meet runs in a browser, so these go to the browser and only work when the Meet tab is the active tab. Otherwise the browser handles "
    "them itself (⌘D bookmarks the page in Chrome/Edge/Brave). The installed Meet web app is safer because its window is the meeting. "
    "Bundle IDs: com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan is the Chrome-installed Meet app (inferred: Chromium's kGoogleMeetAppId "
    "plus Chrome's 'com.google.Chrome.app.<app id>' shim format; not installed here). Chrome, Safari, Edge and Brave are verified on this Mac; "
    "Arc (company.thebrowser.Browser) and Firefox (org.mozilla.firefox) are not installed here. "
    "Windows: match the browser process (chrome.exe, msedge.exe, brave.exe, firefox.exe, Arc.exe). Full list in a call: Shift+?.",
    [
        A("meet.mute", "Mute / Unmute", ("D", "cmd"), "Ctrl+D", "mic.slash.fill", "R"),
        A("meet.camera", "Camera On / Off", ("E", "cmd"), "Ctrl+E", "video.slash.fill", "R"),
        A("meet.raiseHand", "Raise / Lower Hand", ("H", "ctrl cmd"), "Ctrl+Alt+H", "hand.raised.fill", "R"),
        A("meet.chat", "Show / Hide Chat", ("C", "ctrl cmd"), "Ctrl+Alt+C", "message", "F"),
        A("meet.participants", "Show / Hide People", ("P", "ctrl cmd"), "Ctrl+Alt+P", "person.2", "F"),
        A("meet.captions", "Captions On / Off", ("C", ""), "C", "captions.bubble", "R", "Plain C (Shift+C also works)."),
        A("meet.present", "Start Presenting", ("T", "ctrl cmd"), "Ctrl+Alt+T", "rectangle.on.rectangle", "F",
          "Opens the browser's share picker, so this stays in the browser."),
        A("meet.pip", "Picture-in-Picture", ("M", "shift"), "Shift+M", "pip.enter", "R"),
        A("meet.moreTiles", "Increase Participant Tiles", ("K", "ctrl cmd"), "Ctrl+Alt+K", "person.2", "R", swift=False),
        A("meet.fewerTiles", "Decrease Participant Tiles", ("J", "ctrl cmd"), "Ctrl+Alt+J", "person.2", "R", swift=False),
        A("meet.pushToTalk", "Push to Talk (hold Space)", "Space (hold)", "Space (hold)",
          notes="Must be held and needs Push to Talk turned on in Meet settings; a ring tap can't do it."),
        A("meet.leave", "Leave Call", None, None, notes="Google documents no leave-call shortcut."),
        A("meet.reactions", "Reactions", None, None,
          notes="No reaction shortcut is documented. Google's shortcut list has none; a Meet Help Community answer says none exists (community post, not documentation). "
                "Shift+R only changes how reactions are heard.", source=MEET_COMMUNITY),
        A("meet.backgroundBlur", "Background Blur / Effects", None, None, notes="No shortcut documented."),
    ])

app("slack", "Slack", ["com.tinyspeck.slackmacgap"], "slack.exe", SLACK,
    "Bundle ID com.tinyspeck.slackmacgap is the documented Slack desktop identifier (not installed here). Slack says custom keyboard shortcuts "
    "aren't possible. Huddle shortcuts cover start/join/leave and mute only; huddle video, screen share and reactions have none. "
    "Shortcuts marked desktop-app-only in Slack's list: Threads, Activity, Upload.",
    [
        A("slack.huddle", "Start / Join / Leave Huddle", ("H", "shift cmd"), "Ctrl+Shift+H", "headphones", "R",
          "One shortcut starts, joins, leaves or ends a huddle in the current conversation."),
        A("slack.huddleMute", "Huddle Mute / Unmute", ("Space", "shift cmd"), "Ctrl+Shift+Space", "mic.slash.fill", "R"),
        A("slack.search", "Search", ("G", "cmd"), "Ctrl+G", "magnifyingglass", "F"),
        A("slack.newMessage", "New Message", ("N", "cmd"), "Ctrl+N", "square.and.pencil", "F"),
        A("slack.unreads", "All Unreads", ("A", "shift cmd"), "Ctrl+Shift+A", "tray.full", "F"),
        A("slack.threads", "Threads", ("T", "shift cmd"), "Ctrl+Shift+T", "bubble.left.and.bubble.right", "F", "Desktop app only."),
        A("slack.activity", "Activity", ("M", "shift cmd"), "Ctrl+Shift+M", "bell", "F", "Desktop app only."),
        A("slack.dms", "Browse DMs", ("K", "shift cmd"), "Ctrl+Shift+2", "message", "F"),
        A("slack.status", "Set Status", ("Y", "shift cmd"), "Ctrl+Shift+Y", "person.crop.circle", "F"),
        A("slack.markAllRead", "Mark All as Read", ("Esc", "shift"), "Shift+Esc", "checkmark.circle", "R"),
        A("slack.nextUnread", "Next Unread Conversation", ("↓", "opt shift"), "Alt+Shift+↓", "arrow.down.circle", "F"),
        A("slack.jumpTo", "Jump to Conversation", None, "Ctrl+K (or Ctrl+T in the desktop app)",
          notes="Listed only in the Windows/Linux table; the Mac table has no entry."),
        A("slack.huddleVideo", "Huddle Camera / Screen Share", None, None, notes="No shortcut documented."),
    ])

app("webex", "Webex", ["Cisco-Systems.Spark"], "CiscoCollabHost.exe", WEBEX,
    "Cisco-Systems.Spark is the documented Webex App identifier (not installed here). CiscoCollabHost.exe is the main Webex App process per "
    "help.webex.com. Cisco: meeting shortcuts only apply to meetings on the Webex Suite meeting platform, not classic Webex Meetings/Webinars. "
    "Shortcuts can be changed, and some made global, under profile picture > Settings > Keyboard Shortcuts. Answer, decline, pause/stop sharing "
    "are global by default. Note the Mac column uses Control (⌃) for several, e.g. video.",
    [
        A("webex.mute", "Mute / Unmute", ("M", "shift cmd"), "Ctrl+M", "mic.slash.fill", "R"),
        A("webex.camera", "Camera On / Off", ("V", "ctrl shift"), "Ctrl+Shift+V", "video.slash.fill", "R"),
        A("webex.raiseHand", "Raise / Lower Hand", ("R", "shift cmd"), "Ctrl+Shift+R", "hand.raised.fill", "R"),
        A("webex.share", "Share Content", ("D", "ctrl shift"), "Ctrl+Shift+D", "rectangle.on.rectangle", "F",
          "Opens the share picker, so this stays in Webex."),
        A("webex.stopShare", "Stop Sharing", ("Z", "ctrl shift"), "Ctrl+Shift+Z", "rectangle.on.rectangle.slash", "R", "Global by default."),
        A("webex.chat", "Open / Close Chat", ("E", "shift cmd"), "Ctrl+E", "message", "F"),
        A("webex.captions", "Closed Captions On / Off", ("A", "ctrl shift"), "Ctrl+Shift+A", "captions.bubble", "R"),
        A("webex.reactionsPanel", "Reactions Panel", ("Y", "shift cmd"), "Ctrl+Shift+Y", "face.smiling", "F"),
        A("webex.thumbsUp", "React: Thumbs Up", ("4", "opt cmd"), "Alt+Shift+4", "hand.thumbsup.fill", "R"),
        A("webex.clap", "React: Clapping Hands", ("5", "opt cmd"), "Alt+Shift+5", "hands.clap.fill", "R", swift=False),
        A("webex.haha", "React: Haha", ("6", "opt cmd"), "Alt+Shift+6", "face.smiling", "R", swift=False),
        A("webex.celebrate", "React: Celebrate", ("7", "opt cmd"), "Alt+Shift+7", "face.smiling", "R", swift=False),
        A("webex.love", "React: Love", ("8", "opt cmd"), "Alt+Shift+8", "heart.fill", "R", swift=False),
        A("webex.endCall", "End Call", ("L", "cmd"), "Ctrl+L", "phone.down.fill", "R",
          "Documented as 'End a call'; no separate leave-meeting shortcut is listed."),
        A("webex.answer", "Answer Call", ("C", "ctrl shift"), "Ctrl+Shift+C", "phone.fill", "F", "Global by default."),
        A("webex.decline", "Decline Call", ("D", "shift cmd"), "Ctrl+D", "phone.down.circle.fill", "R", "Global by default."),
        A("webex.pauseShare", "Pause / Resume Sharing", ("S", "ctrl shift"), "Alt+Shift+S", "pause.rectangle", "R", swift=False),
        A("webex.backgroundBlur", "Background Blur", None, None, notes="No shortcut documented."),
    ])

app("facetime", "FaceTime", ["com.apple.FaceTime"], None, FACETIME,
    "Bundle ID verified on this Mac. Mac only. Apple documents only window shortcuts for FaceTime: there is no documented shortcut for mute, "
    "camera, end, accept/decline, screen sharing, reactions or captions.",
    [
        A("facetime.fullScreen", "Full Screen", ("F", "ctrl cmd"), None, "arrow.up.left.and.arrow.down.right", "F", "During a video call."),
        A("facetime.rotate", "Landscape / Portrait", ("R", "cmd"), None, "rectangle.portrait.rotate", "F", "During a one-on-one video call."),
        A("facetime.close", "Close FaceTime Window", ("W", "cmd"), None, "xmark.square", "F"),
        A("facetime.mute", "Mute / Camera / End Call", None, None, notes="Not documented; use the on-screen call controls."),
    ])

app("discord", "Discord", ["com.hnc.Discord"], "Discord.exe", DISCORD,
    "com.hnc.Discord is the documented Discord identifier (not installed here). Source is Discord's own blog (Nov 2024); support.discord.com blocks "
    "automated reading. Desktop app: shortcuts work even when Discord isn't focused, and mute/deafen are listed as working in the background. "
    "Push to talk and other voice keybinds have to be set up in User Settings > Keybinds.",
    [
        A("discord.mute", "Mute / Unmute", ("M", "shift cmd"), "Ctrl+Shift+M", "mic.slash.fill", "R"),
        A("discord.deafen", "Deafen / Undeafen", ("D", "shift cmd"), "Ctrl+Shift+D", "speaker.slash.fill", "R"),
        A("discord.answer", "Answer Call", ("Return", "cmd"), "Ctrl+Enter", "phone.fill", "F"),
        A("discord.decline", "Decline Call", ("Esc", ""), "Esc", "phone.down.fill", "R"),
        A("discord.currentCall", "Jump to Current Call", ("V", "opt shift cmd"), "Ctrl+Shift+Alt+V", "arrowshape.turn.up.right.circle", "F"),
        A("discord.soundboard", "Soundboard", ("B", "shift cmd"), "Ctrl+Shift+B", "speaker.wave.2", "F", "In a call."),
        A("discord.quickSwitcher", "Quick Switcher", ("K", "cmd"), "Ctrl+K", "magnifyingglass", "F"),
        A("discord.emoji", "Emoji Picker", ("E", "cmd"), "Ctrl+E", "face.smiling", "F"),
        A("discord.upload", "Attach File", ("U", "shift cmd"), "Ctrl+Shift+U", "paperclip", "F"),
        A("discord.shortcuts", "Show Shortcuts", ("/", "cmd"), "Ctrl+/", "keyboard", "F"),
        A("discord.callDM", "Call This DM", None, "Ctrl+'", notes="Discord lists only Ctrl + ' with no Mac variant."),
        A("discord.camera", "Camera / Screen Share", None, None, notes="No default shortcut; can be bound in User Settings > Keybinds."),
        A("discord.pushToTalk", "Push to Talk", None, None, notes="Needs a keybind set up in User Settings > Keybinds, and must be held."),
    ])

# ================================================================ Office / productivity
app("outlook", "Microsoft Outlook", ["com.microsoft.Outlook"], "olk.exe", OUTLOOK_MAC,
    "Bundle ID verified on this Mac (16.114). Mac page covers Outlook for Microsoft 365 / 2024 / 2021 for Mac. Windows column is new Outlook "
    "(olk.exe); classic Outlook (OUTLOOK.EXE) differs where noted. Windows process names not verified on a Windows PC.",
    [
        A("outlook.newMessage", "New Message", ("N", "cmd"), "Ctrl+N", "square.and.pencil", "F"),
        A("outlook.reply", "Reply", ("R", "cmd"), "Ctrl+R", "arrowshape.turn.up.left", "F"),
        A("outlook.replyAll", "Reply All", ("R", "shift cmd"), "Ctrl+Shift+R", "arrowshape.turn.up.left.2", "F"),
        A("outlook.forward", "Forward", ("J", "cmd"), "Ctrl+F", "arrowshape.turn.up.right", "F"),
        A("outlook.archive", "Archive", ("E", "ctrl"), None, "archivebox", "F", "Not listed for Windows."),
        A("outlook.markRead", "Mark as Read", ("T", "cmd"), "Ctrl+Q", "envelope.open", "F"),
        A("outlook.markUnread", "Mark as Unread", ("T", "shift cmd"), "Ctrl+U", "envelope.badge", "F"),
        A("outlook.flag", "Flag for Follow Up", ("=", "ctrl"), "Insert", "flag", "F", "Mac: flag with a reminder. ⌃5 flags with no due date."),
        A("outlook.move", "Move to Folder", ("M", "shift cmd"), None, "folder", "F", "Windows: classic Outlook Ctrl+Shift+V; none listed for new Outlook."),
        A("outlook.mail", "Go to Mail", ("1", "cmd"), "Ctrl+1", "envelope", "F"),
        A("outlook.calendar", "Go to Calendar", ("2", "cmd"), "Ctrl+2", "calendar", "F"),
        A("outlook.sync", "Send & Receive", ("K", "ctrl cmd"), None, "arrow.clockwise", "F",
          "Windows: classic Outlook F9 or Ctrl+M; none listed for new Outlook."),
        A("outlook.send", "Send", ("Return", "cmd"), "Ctrl+Enter", "paperplane", "F", swift=False),
        A("outlook.people", "Go to Contacts / People", ("3", "cmd"), "Ctrl+4", "person.2", "F", swift=False),
    ], windowsSource=OUTLOOK_WIN)

app("word", "Microsoft Word", ["com.microsoft.Word"], "WINWORD.EXE", WORD,
    "Bundle ID verified on this Mac (16.114). Applies to Word for Microsoft 365 / 2024 for Mac and Windows. Custom shortcuts can be created on both "
    "(Mac: Tools > Customize Keyboard).",
    [
        A("word.save", "Save", ("S", "cmd"), "Ctrl+S", "square.and.arrow.down", "F", "Mac: Microsoft's Common Office for Mac shortcuts page.", source=OFFICE_MAC),
        A("word.trackChanges", "Track Changes On / Off", ("E", "shift cmd"), "Ctrl+Shift+E", "text.badge.checkmark", "F"),
        A("word.comment", "New Comment", ("A", "opt cmd"), "Ctrl+Alt+M", "text.bubble", "F"),
        A("word.find", "Find", ("F", "cmd"), "Ctrl+F", "magnifyingglass", "F"),
        A("word.replace", "Find & Replace", ("H", "ctrl"), "Ctrl+H", "magnifyingglass", "F"),
        A("word.spelling", "Spelling & Grammar", ("L", "opt cmd"), "F7", "textformat.abc", "F", "Mac also F7."),
        A("word.pageBreak", "Page Break", ("Return", "cmd"), "Ctrl+Enter", "doc.badge.plus", "F"),
        A("word.heading1", "Heading 1", ("1", "opt cmd"), "Ctrl+Alt+1", "textformat.size", "F"),
        A("word.print", "Print", ("P", "cmd"), "Ctrl+P", "printer", "F"),
        A("word.formattingMarks", "Show Formatting Marks", None, "Ctrl+Shift+8", notes="No Mac shortcut listed."),
        A("word.hyperlink", "Insert Link", None, "Ctrl+K", notes="No Mac shortcut listed on Microsoft's page."),
        A("word.clearFormatting", "Clear Character Formatting", None, "Ctrl+Space", notes="No Mac shortcut listed."),
    ])

app("excel", "Microsoft Excel", ["com.microsoft.Excel"], "EXCEL.EXE", EXCEL,
    "Bundle ID verified on this Mac (16.114). Mac uses ⌃ (Control) for several of these, as Microsoft lists them.",
    [
        A("excel.save", "Save", ("S", "cmd"), "Ctrl+S", "square.and.arrow.down", "F"),
        A("excel.autoSum", "AutoSum", ("T", "shift cmd"), "Alt+=", "sum", "F"),
        A("excel.filter", "Filter On / Off", ("F", "shift cmd"), None, "line.3.horizontal.decrease.circle", "F",
          "Mac only on Microsoft's page. Ctrl+Shift+L for Windows is widely quoted but isn't on Microsoft's current page."),
        A("excel.formatCells", "Format Cells", ("1", "cmd"), "Ctrl+1", "tablecells", "F"),
        A("excel.fillDown", "Fill Down", ("D", "ctrl"), "Ctrl+D", "arrow.down.to.line", "F"),
        A("excel.insertCells", "Insert Cells", ("=", "ctrl shift"), "Ctrl+Shift+Plus (+)", "plus.square", "F"),
        A("excel.deleteCells", "Delete Cells", ("-", "cmd"), "Ctrl+Minus (-)", "minus.square", "F"),
        A("excel.note", "New Note", ("F2", "shift"), "Shift+F2", "note.text", "F"),
        A("excel.comment", "New Threaded Comment", ("F2", "shift cmd"), "Ctrl+Shift+F2", "text.bubble", "F"),
        A("excel.pasteSpecial", "Paste Special", ("V", "ctrl cmd"), "Ctrl+Alt+V", "doc.on.clipboard", "F"),
        A("excel.calculate", "Calculate Now", ("=", "cmd"), "F9", "function", "F", "Mac: calculate all open workbooks."),
        A("excel.date", "Insert Current Date", None, "Ctrl+;", notes="No Mac shortcut on Microsoft's current page."),
        A("excel.time", "Insert Current Time", None, "Ctrl+Shift+:", notes="No Mac shortcut on Microsoft's current page."),
    ])

app("powerpoint", "Microsoft PowerPoint", ["com.microsoft.Powerpoint"], "POWERPNT.EXE", PPT_SHOW,
    "Bundle ID verified on this Mac (16.114; note the lowercase 'p'). Slide-show keys only work while the show is running.",
    [
        A("ppt.playFromStart", "Play from Start", ("Return", "shift cmd"), "F5", "play.fill", "F"),
        A("ppt.playFromCurrent", "Play from Current Slide", ("Return", "cmd"), "Shift+F5", "play", "F"),
        A("ppt.presenterView", "Presenter View", ("Return", "opt"), "Alt+F5", "play.rectangle", "F"),
        A("ppt.next", "Next Slide", ("→", ""), "→ (or N, Space, Page Down)", "chevron.right", "F"),
        A("ppt.previous", "Previous Slide", ("←", ""), "← (or P, Page Up)", "chevron.left", "F"),
        A("ppt.black", "Black Screen", ("B", ""), "B", "rectangle.fill", "F"),
        A("ppt.white", "White Screen", ("W", ""), "W", "rectangle", "F"),
        A("ppt.laser", "Laser Pointer", ("L", "cmd"), "Ctrl+L", "laser.burst", "F"),
        A("ppt.end", "End Slide Show", ("Esc", ""), "Esc", "xmark.circle", "F"),
        A("ppt.newSlide", "New Slide", ("N", "shift cmd"), "Ctrl+M", "rectangle.badge.plus", "F", source=PPT_CREATE),
        A("ppt.comment", "New Comment", ("M", "shift cmd"), "Ctrl+Alt+M", "text.bubble", "F", source=PPT_CREATE),
        A("ppt.save", "Save", ("S", "cmd"), "Ctrl+S", "square.and.arrow.down", "F", source=PPT_CREATE),
    ])

app("keynote", "Keynote", ["com.apple.iWork.Keynote"], None, KEYNOTE,
    "Bundle ID verified on this Mac (14.5). Mac only. Presenter keys (arrows, B, W, Esc) work while the presentation is playing.",
    [
        A("keynote.play", "Play Slideshow", ("P", "opt cmd"), None, "play.fill", "F"),
        A("keynote.next", "Next Slide / Build", ("→", ""), None, "chevron.right", "F"),
        A("keynote.previous", "Previous Slide", ("←", ""), None, "chevron.left", "F"),
        A("keynote.notes", "Show / Hide Presenter Notes", ("P", "shift cmd"), None, "note.text", "F", "While playing."),
        A("keynote.black", "Black Screen", ("B", ""), None, "rectangle.fill", "F"),
        A("keynote.white", "White Screen", ("W", ""), None, "rectangle", "F"),
        A("keynote.stop", "Quit Presentation", ("Esc", ""), None, "xmark.circle", "F", "Esc or Q."),
        A("keynote.newSlide", "New Slide", ("N", "shift cmd"), None, "rectangle.badge.plus", "F", "In the slide navigator."),
        A("keynote.skip", "Skip / Unskip Slide", ("H", "shift cmd"), None, "eye.slash", "F"),
        A("keynote.save", "Save", ("S", "cmd"), None, "square.and.arrow.down", "F"),
    ])

app("notion", "Notion", ["notion.id"], "Notion.exe", NOTION,
    "Bundle ID verified on this Mac (7.12). Notion writes 'cmd/ctrl': Command on Mac, Control on Windows. Listed for English/QWERTY keyboards.",
    [
        A("notion.search", "Search", ("P", "cmd"), "Ctrl+P", "magnifyingglass", "F", "⌘K also opens search."),
        A("notion.newPage", "New Page", ("N", "cmd"), "Ctrl+N", "square.and.pencil", "F", "Desktop app."),
        A("notion.newTab", "New Tab", ("T", "cmd"), "Ctrl+T", "plus.rectangle.on.rectangle", "F", "Desktop app."),
        A("notion.newWindow", "New Window", ("N", "shift cmd"), "Ctrl+Shift+N", "macwindow", "F", "Desktop app."),
        A("notion.copyLink", "Copy Page Link", ("L", "cmd"), "Ctrl+L", "link", "F"),
        A("notion.back", "Back", ("[", "cmd"), "Ctrl+[", "arrow.left", "F"),
        A("notion.forward", "Forward", ("]", "cmd"), "Ctrl+]", "arrow.right", "F"),
        A("notion.darkMode", "Dark / Light Mode", ("L", "shift cmd"), "Ctrl+Shift+L", "circle.lefthalf.filled", "F"),
        A("notion.comment", "New Comment", ("M", "shift cmd"), "Ctrl+Shift+M", "text.bubble", "F"),
    ])

app("figma", "Figma", ["com.figma.Desktop"], "Figma.exe", FIGMA_KEYBOARD,
    "Bundle ID verified on this Mac (126.10). Figma has no single shortcut page; each entry cites the help article that documents it. "
    "Figma remaps some shortcuts for non-US keyboard layouts.",
    [
        A("figma.actions", "Actions Menu", ("K", "cmd"), "Ctrl+K", "command", "F", source=FIGMA_ACTIONS),
        A("figma.createComponent", "Create Component", ("K", "opt cmd"), "Ctrl+Alt+K", "square.on.square", "F", source=FIGMA_COMPONENTS),
        A("figma.frameSelection", "Frame Selection", ("G", "opt cmd"), "Ctrl+Alt+G", "square.dashed", "F", source=FIGMA_FRAMES),
        A("figma.ungroup", "Ungroup / Unframe", ("G", "shift cmd"), "Ctrl+Shift+G", "square.3.layers.3d", "F", source=FIGMA_FRAMES),
        A("figma.duplicate", "Duplicate", ("D", "cmd"), "Ctrl+D", "plus.square.on.square", "F", source=FIGMA_FRAMES),
        A("figma.resizeToFit", "Resize Frame to Fit", ("R", "opt shift cmd"), "Ctrl+Alt+Shift+R", "rectangle.compress.vertical", "F", source=FIGMA_FRAMES),
        A("figma.autoLayout", "Add Auto Layout", ("A", "shift"), "Shift+A", "rectangle.split.2x1", "F", source=FIGMA_AUTOLAYOUT),
        A("figma.removeAutoLayout", "Remove Auto Layout", ("A", "opt shift"), "Alt+Shift+A", "rectangle", "F", source=FIGMA_AUTOLAYOUT),
        A("figma.export", "Export", ("E", "shift cmd"), "Ctrl+Shift+E", "square.and.arrow.up", "F", source=FIGMA_EXPORT),
        A("figma.shortcuts", "Keyboard Shortcuts Panel", ("/", "ctrl shift"), "Ctrl+Shift+?", "keyboard", "F",
          "Figma writes Control Shift ?; on a US keyboard ? is Shift-/.", source=FIGMA_KEYBOARD),
    ])

# ================================================================ creative
app("photoshop", "Adobe Photoshop", ["com.adobe.Photoshop"], "Photoshop.exe", PS,
    "com.adobe.Photoshop is the documented identifier (not installed here). Adobe's current page (updated Sep 2026) only says to open "
    "Edit > Keyboard Shortcuts (⌥⇧⌘K); the full default list is Adobe's shortcut PDF (dated Jul 2022), still hosted on helpx.adobe.com. "
    "Defaults can be customized in Photoshop.",
    [
        A("ps.brush", "Brush Tool", ("B", ""), "B", "paintbrush.fill", "F"),
        A("ps.eraser", "Eraser Tool", ("E", ""), "E", "eraser.fill", "F"),
        A("ps.move", "Move Tool", ("V", ""), "V", "arrow.up.and.down.and.arrow.left.and.right", "F"),
        A("ps.freeTransform", "Free Transform", ("T", "cmd"), "Ctrl+T", "skew", "F"),
        A("ps.deselect", "Deselect", ("D", "cmd"), "Ctrl+D", "square.dashed", "F"),
        A("ps.inverse", "Inverse Selection", ("F7", "shift"), "Shift+F7", "selection.pin.in.out", "F"),
        A("ps.newLayer", "New Layer", ("N", "shift cmd"), "Ctrl+Shift+N", "square.3.layers.3d", "F"),
        A("ps.layerViaCopy", "New Layer via Copy", ("J", "cmd"), "Ctrl+J", "plus.square.on.square", "F"),
        A("ps.mergeVisible", "Merge Visible", ("E", "shift cmd"), "Ctrl+Shift+E", "arrow.triangle.merge", "F"),
        A("ps.group", "Group Layers", ("G", "cmd"), "Ctrl+G", "folder.badge.plus", "F"),
        A("ps.swapColors", "Swap Colors", ("X", ""), "X", "arrow.left.arrow.right", "F"),
        A("ps.undo", "Undo", ("Z", "cmd"), "Ctrl+Z", "arrow.uturn.backward", "F"),
        A("ps.brushSize", "Smaller Brush", "[", "[",
          notes="The PDF lists [ for smaller; the larger-brush key didn't come through when the PDF was read, so neither is a preset."),
    ])

app("lightroom", "Adobe Lightroom Classic", ["com.adobe.LightroomClassicCC7"], "Lightroom.exe", LRC,
    "com.adobe.LightroomClassicCC7 is the documented identifier (not installed here). Page last updated Oct 29, 2025.",
    [
        A("lrc.library", "Library Module", ("1", "opt cmd"), "Ctrl+Alt+1", "photo.on.rectangle", "F"),
        A("lrc.develop", "Develop Module", ("2", "opt cmd"), "Ctrl+Alt+2", "slider.horizontal.3", "F"),
        A("lrc.pick", "Flag as Pick", ("P", ""), "P", "flag.fill", "F"),
        A("lrc.reject", "Flag as Reject", ("X", ""), "X", "xmark.bin", "F"),
        A("lrc.unflag", "Unflag", ("U", ""), "U", "flag.slash", "F"),
        A("lrc.beforeAfter", "Before / After", ("Y", ""), "Y", "rectangle.split.2x1", "F", "Develop: left/right view."),
        A("lrc.autoTone", "Auto Tone", ("U", "cmd"), "Ctrl+U", "wand.and.stars", "F"),
        A("lrc.copySettings", "Copy Develop Settings", ("C", "shift cmd"), "Ctrl+Shift+C", "doc.on.doc", "F"),
        A("lrc.pasteSettings", "Paste Develop Settings", ("V", "shift cmd"), "Ctrl+Shift+V", "doc.on.clipboard", "F"),
        A("lrc.virtualCopy", "Create Virtual Copy", ("'", "cmd"), "Ctrl+'", "plus.square.on.square", "F"),
        A("lrc.crop", "Crop Tool", ("R", ""), "R", "crop", "F"),
        A("lrc.export", "Export", ("E", "shift cmd"), "Ctrl+Shift+E", "square.and.arrow.up", "F"),
    ])

app("premiere", "Adobe Premiere Pro", ["com.adobe.PremierePro.26", "com.adobe.PremierePro.25", "com.adobe.PremierePro.24"],
    "Adobe Premiere Pro.exe", PR,
    "Not installed here. Adobe puts the release year in the identifier (com.adobe.PremierePro.24 = 2024, .25 = 2025); .26 for the 2026 release is "
    "inferred from that pattern. Adobe now calls the app 'Premiere'; page last updated Jan 7, 2026. Shortcuts are panel-specific (most of these need "
    "the Timeline focused).",
    [
        A("pr.playStop", "Play / Stop", ("Space", ""), "Space", "play.fill", "F"),
        A("pr.addEdit", "Add Edit (Cut at Playhead)", ("K", "cmd"), "Ctrl+K", "scissors", "F"),
        A("pr.rippleDelete", "Ripple Delete", ("Delete", "opt"), "Alt+Backspace", "delete.left", "F",
          "Timeline panel entry. The Edit menu lists Shift+Forward Delete (Mac) / Shift+Delete (Windows), which a ring preset can't send on Mac."),
        A("pr.markIn", "Mark In", ("I", ""), "I", "arrow.right.to.line", "F"),
        A("pr.markOut", "Mark Out", ("O", ""), "O", "arrow.left.to.line", "F"),
        A("pr.marker", "Add Marker", ("M", ""), "M", "bookmark", "F"),
        A("pr.snap", "Snap On / Off", ("S", ""), "S", "arrow.right.and.line.vertical.and.arrow.left", "F"),
        A("pr.transition", "Apply Video Transition", ("D", "cmd"), "Ctrl+D", "square.on.square", "F"),
        A("pr.export", "Export Media", ("M", "cmd"), "Ctrl+M", "square.and.arrow.up", "F"),
        A("pr.undo", "Undo", ("Z", "cmd"), "Ctrl+Z", "arrow.uturn.backward", "F"),
        A("pr.redo", "Redo", ("Z", "shift cmd"), "Ctrl+Shift+Z", "arrow.uturn.forward", "F"),
        A("pr.save", "Save", ("S", "cmd"), "Ctrl+S", "square.and.arrow.down", "F"),
    ])

app("finalcut", "Final Cut Pro", ["com.apple.FinalCut"], None, FCP,
    "com.apple.FinalCut is the documented identifier (not installed here). Mac only. Guide covers Final Cut Pro for Mac 12.x. Shortcuts can be "
    "changed in the Command Editor.",
    [
        A("fcp.playPause", "Play / Pause", ("Space", ""), None, "play.fill", "F"),
        A("fcp.blade", "Blade (Cut at Playhead)", ("B", "cmd"), None, "scissors", "F"),
        A("fcp.bladeAll", "Blade All", ("B", "shift cmd"), None, "scissors", "F"),
        A("fcp.marker", "Add Marker", ("M", ""), None, "bookmark", "F"),
        A("fcp.rangeStart", "Set Range Start", ("I", ""), None, "arrow.right.to.line", "F"),
        A("fcp.rangeEnd", "Set Range End", ("O", ""), None, "arrow.left.to.line", "F"),
        A("fcp.snapping", "Snapping On / Off", ("N", ""), None, "arrow.right.and.line.vertical.and.arrow.left", "F"),
        A("fcp.skimming", "Skimming On / Off", ("S", ""), None, "waveform", "F"),
        A("fcp.zoomToFit", "Zoom to Fit", ("Z", "shift"), None, "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "F"),
        A("fcp.undo", "Undo", ("Z", "cmd"), None, "arrow.uturn.backward", "F"),
        A("fcp.share", "Share to Default Destination", ("E", "cmd"), None, "square.and.arrow.up", "F"),
        A("fcp.import", "Import Media", ("I", "cmd"), None, "square.and.arrow.down", "F"),
    ])

app("resolve", "DaVinci Resolve", ["com.blackmagic-design.DaVinciResolve"], "Resolve.exe", RESOLVE,
    "Bundle ID verified on this Mac (21.0.2). Caveat: the only standalone shortcut list Blackmagic publishes is its 'DaVinci Resolve 11 Menus & "
    "Keyboard Shortcuts' guide (now hosted as DaVinci-Resolve-15-Keyboard-Shortcuts.pdf). The current Resolve 20/21 Reference Manual (209 MB) wasn't "
    "downloaded. Only long-standing keys are included (JKL, I/O, M, ⌘B, B, N, ⇧Z, ⌘Z, ⌘S). Check DaVinci Resolve > Keyboard Customization before relying on them. "
    "The guide says Windows uses Control instead of Command and Alt instead of Option. Shortcuts are page-specific (Edit page).",
    [
        A("resolve.playReverse", "Play Reverse", ("J", ""), "J", "backward.fill", "F"),
        A("resolve.stop", "Stop", ("K", ""), "K", "stop.fill", "F"),
        A("resolve.playForward", "Play Forward", ("L", ""), "L", "forward.fill", "F"),
        A("resolve.markIn", "Mark In", ("I", ""), "I", "arrow.right.to.line", "F"),
        A("resolve.markOut", "Mark Out", ("O", ""), "O", "arrow.left.to.line", "F"),
        A("resolve.marker", "Add Marker", ("M", ""), "M", "bookmark", "F"),
        A("resolve.razor", "Razor (Cut at Playhead)", ("B", "cmd"), "Ctrl+B", "scissors", "F"),
        A("resolve.blade", "Blade Edit Mode", ("B", ""), "B", "scissors.badge.ellipsis", "F"),
        A("resolve.snapping", "Snapping On / Off", ("N", ""), "N", "arrow.right.and.line.vertical.and.arrow.left", "F"),
        A("resolve.zoomToFit", "Zoom to Fit", ("Z", "shift"), "Shift+Z", "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "F"),
        A("resolve.undo", "Undo", ("Z", "cmd"), "Ctrl+Z", "arrow.uturn.backward", "F"),
        A("resolve.save", "Save Project", ("S", "cmd"), "Ctrl+S", "square.and.arrow.down", "F"),
        A("resolve.splitClip", "Split Clip", ("\\", "cmd"), "Ctrl+\\", "scissors", "F", swift=False),
    ])

# ================================================================ developer
app("vscode", "Visual Studio Code", ["com.microsoft.VSCode"], "Code.exe", VSCODE_MAC,
    "Bundle ID verified on this Mac (1.124). Source is VS Code's official keyboard-shortcut reference PDFs (linked from code.visualstudio.com; "
    "the PDFs date from 2021, and these defaults are unchanged since). Keybindings are user-customizable (keybindings.json).",
    [
        A("vscode.commandPalette", "Command Palette", ("P", "shift cmd"), "Ctrl+Shift+P", "command", "F"),
        A("vscode.quickOpen", "Quick Open File", ("P", "cmd"), "Ctrl+P", "magnifyingglass", "F"),
        A("vscode.terminal", "Show Terminal", ("`", "ctrl"), "Ctrl+`", "terminal", "F"),
        A("vscode.sidebar", "Toggle Sidebar", ("B", "cmd"), "Ctrl+B", "sidebar.left", "F"),
        A("vscode.explorer", "Explorer", ("E", "shift cmd"), "Ctrl+Shift+E", "folder", "F"),
        A("vscode.search", "Search in Files", ("F", "shift cmd"), "Ctrl+Shift+F", "magnifyingglass", "F"),
        A("vscode.sourceControl", "Source Control", ("G", "ctrl shift"), "Ctrl+Shift+G", "arrow.triangle.branch", "F"),
        A("vscode.format", "Format Document", ("F", "opt shift"), "Shift+Alt+F", "text.alignleft", "F"),
        A("vscode.comment", "Toggle Line Comment", ("/", "cmd"), "Ctrl+/", "chevron.left.forwardslash.chevron.right", "F"),
        A("vscode.split", "Split Editor", ("\\", "cmd"), "Ctrl+\\", "square.split.2x1", "F"),
        A("vscode.wordWrap", "Toggle Word Wrap", ("Z", "opt"), "Alt+Z", "text.word.spacing", "F"),
        A("vscode.debug", "Start / Continue Debugging", ("F5", ""), "F5", "ladybug", "F"),
    ], windowsSource=VSCODE_WIN)

app("xcode", "Xcode", ["com.apple.dt.Xcode"], None, XCODE_WWDC,
    "com.apple.dt.Xcode is the documented identifier (not installed here). Mac only. Apple has no current shortcut page for Xcode. Sources: "
    "WWDC24 'Xcode essentials' (Apple, 2024) and Apple's archived Xcode shortcut reference (old; only entries that match current Xcode are used: "
    "that archive also lists Test as ⌘T, which is outdated). All bindings can be changed in Xcode Settings > Key Bindings.",
    [
        A("xcode.build", "Build", ("B", "cmd"), None, "hammer", "F", source=XCODE_ARCHIVE),
        A("xcode.run", "Run", ("R", "cmd"), None, "play.fill", "F", source=XCODE_ARCHIVE),
        A("xcode.stop", "Stop", (".", "cmd"), None, "stop.fill", "F", source=XCODE_ARCHIVE),
        A("xcode.test", "Test", ("U", "cmd"), None, "checkmark.diamond", "F"),
        A("xcode.runWithoutBuilding", "Run Without Building", ("R", "ctrl cmd"), None, "play", "F"),
        A("xcode.clean", "Clean Build Folder", ("K", "shift cmd"), None, "trash", "F",
          "The archived reference calls ⇧⌘K 'Clean'; current Xcode's Product menu names it Clean Build Folder (inferred from current Xcode).",
          source=XCODE_ARCHIVE),
        A("xcode.openQuickly", "Open Quickly", ("O", "shift cmd"), None, "magnifyingglass", "F"),
        A("xcode.findNavigator", "Find in Project", ("F", "shift cmd"), None, "text.magnifyingglass", "F"),
        A("xcode.quickActions", "Quick Actions", ("A", "shift cmd"), None, "command", "F"),
        A("xcode.debugArea", "Show / Hide Debug Area", ("Y", "shift cmd"), None, "rectangle.bottomthird.inset.filled", "F", source=XCODE_ARCHIVE),
        A("xcode.comment", "Comment Selection", ("/", "cmd"), None, "chevron.left.forwardslash.chevron.right", "F", source=XCODE_ARCHIVE),
    ])

# ================================================================ browsers
app("chrome", "Google Chrome", ["com.google.Chrome"], "chrome.exe", CHROME,
    "Bundle ID verified on this Mac (156.0). Google's Mac list doesn't include plain reload (⌘R); it lists ⇧⌘R (reload ignoring cache).",
    [
        A("chrome.newTab", "New Tab", ("T", "cmd"), "Ctrl+T", "plus.square.on.square", "F"),
        A("chrome.reopenTab", "Reopen Closed Tab", ("T", "shift cmd"), "Ctrl+Shift+T", "arrow.uturn.backward", "F"),
        A("chrome.closeTab", "Close Tab", ("W", "cmd"), "Ctrl+W", "xmark.square", "F"),
        A("chrome.nextTab", "Next Tab", ("→", "opt cmd"), "Ctrl+Tab", "arrow.right.square", "F"),
        A("chrome.previousTab", "Previous Tab", ("←", "opt cmd"), "Ctrl+Shift+Tab", "arrow.left.square", "F"),
        A("chrome.incognito", "New Incognito Window", ("N", "shift cmd"), "Ctrl+Shift+N", "eyeglasses", "F"),
        A("chrome.addressBar", "Address Bar", ("L", "cmd"), "Ctrl+L", "link", "F"),
        A("chrome.bookmark", "Bookmark Page", ("D", "cmd"), "Ctrl+D", "bookmark", "F"),
        A("chrome.history", "History", ("Y", "cmd"), "Ctrl+H", "clock.arrow.circlepath", "F"),
        A("chrome.downloads", "Downloads", ("J", "shift cmd"), "Ctrl+J", "arrow.down.circle", "F"),
        A("chrome.hardReload", "Reload (Ignore Cache)", ("R", "shift cmd"), "Ctrl+Shift+R", "arrow.clockwise", "F"),
        A("chrome.devTools", "Developer Tools", ("I", "opt cmd"), "Ctrl+Shift+J (or F12)", "chevron.left.forwardslash.chevron.right", "F"),
    ])

app("safari", "Safari", ["com.apple.Safari"], None, SAFARI,
    "Bundle ID verified on this Mac (27.2). Mac only. Apple's Safari page doesn't list ⌘T or ⌘R, so they're not included.",
    [
        A("safari.tabOverview", "Tab Overview", ("\\", "shift cmd"), None, "square.grid.2x2", "F"),
        A("safari.nextTab", "Next Tab", ("]", "shift cmd"), None, "arrow.right.square", "F", "Also ⌃Tab."),
        A("safari.previousTab", "Previous Tab", ("[", "shift cmd"), None, "arrow.left.square", "F", "Also ⌃⇧Tab."),
        A("safari.closeTab", "Close Tab", ("W", "cmd"), None, "xmark.square", "F"),
        A("safari.reopenTab", "Reopen Last Closed Tab", ("T", "shift cmd"), None, "arrow.uturn.backward", "F"),
        A("safari.searchField", "Smart Search Field", ("L", "cmd"), None, "link", "F"),
        A("safari.find", "Find on Page", ("F", "cmd"), None, "magnifyingglass", "F"),
        A("safari.back", "Back", ("[", "cmd"), None, "arrow.left", "F"),
        A("safari.forward", "Forward", ("]", "cmd"), None, "arrow.right", "F"),
        A("safari.reader", "Reader", ("R", "shift cmd"), None, "text.book.closed", "F"),
        A("safari.readingList", "Add to Reading List", ("D", "shift cmd"), None, "eyeglasses", "F"),
        A("safari.home", "Homepage", ("H", "shift cmd"), None, "house", "F"),
    ])

app("arc", "Arc", ["company.thebrowser.Browser"], "Arc.exe", ARC,
    "company.thebrowser.Browser is the documented identifier (not installed here). Arc's own Keyboard Shortcuts article "
    "(resources.arc.net/hc/en-us/articles/20595231349911) is no longer online (404 on 2026-10-28). Source is the Wayback Machine copy from "
    "2026-07-25. Arc lets you remap shortcuts in Settings. Arc.exe for Windows is not verified on a Windows PC.",
    [
        A("arc.newTab", "New Tab", ("T", "cmd"), "Ctrl+T", "plus.square.on.square", "F"),
        A("arc.littleArc", "Little Arc", ("N", "opt cmd"), None, "macwindow", "F", "Mac only."),
        A("arc.reopenTab", "Reopen Closed Tab", ("T", "shift cmd"), "Ctrl+Shift+T", "arrow.uturn.backward", "F"),
        A("arc.closeTab", "Close Tab", ("W", "cmd"), "Ctrl+W", "xmark.square", "F"),
        A("arc.pinTab", "Pin / Unpin Tab", ("D", "cmd"), "Ctrl+D", "pin", "F"),
        A("arc.copyURL", "Copy URL", ("C", "shift cmd"), "Ctrl+Shift+C", "link", "F"),
        A("arc.sidebar", "Show / Hide Sidebar", ("S", "cmd"), "Ctrl+S", "sidebar.left", "F"),
        A("arc.clearTabs", "Clear Unpinned Tabs", ("K", "shift cmd"), "Ctrl+Shift+K", "xmark.bin", "F"),
        A("arc.splitView", "Add Split View", ("=", "ctrl shift"), "Ctrl+Shift+Plus (+)", "rectangle.split.2x1", "F",
          "Arc writes Control-Shift-Plus; + is Shift-= on a US keyboard."),
        A("arc.closeSplit", "Close Split View", ("-", "ctrl shift"), "Ctrl+Shift+Minus (-)", "rectangle", "F"),
        A("arc.nextSpace", "Next Space", ("→", "opt cmd"), "Ctrl+Alt+→", "arrow.right.circle", "F"),
        A("arc.previousSpace", "Previous Space", ("←", "opt cmd"), "Ctrl+Alt+←", "arrow.left.circle", "F"),
    ])

app("edge", "Microsoft Edge", ["com.microsoft.edgemac"], "msedge.exe", EDGE,
    "Bundle ID verified on this Mac (156.0).",
    [
        A("edge.newTab", "New Tab", ("T", "cmd"), "Ctrl+T", "plus.square.on.square", "F"),
        A("edge.reopenTab", "Reopen Closed Tab", ("T", "shift cmd"), "Ctrl+Shift+T", "arrow.uturn.backward", "F"),
        A("edge.closeTab", "Close Tab", ("W", "cmd"), "Ctrl+W", "xmark.square", "F"),
        A("edge.reload", "Reload", ("R", "cmd"), "Ctrl+R", "arrow.clockwise", "F"),
        A("edge.inPrivate", "New InPrivate Window", ("N", "shift cmd"), "Ctrl+Shift+N", "eyeglasses", "F"),
        A("edge.addressBar", "Address Bar", ("L", "cmd"), "Ctrl+L", "link", "F"),
        A("edge.favorite", "Add to Favorites", ("D", "cmd"), "Ctrl+D", "star", "F"),
        A("edge.favoritesBar", "Show / Hide Favorites Bar", ("B", "shift cmd"), "Ctrl+Shift+B", "star.square", "F"),
        A("edge.history", "History", ("Y", "cmd"), "Ctrl+H", "clock.arrow.circlepath", "F"),
        A("edge.downloads", "Downloads", ("L", "opt cmd"), "Ctrl+J", "arrow.down.circle", "F"),
        A("edge.readAloud", "Read Aloud", ("U", "shift cmd"), "Ctrl+Shift+U", "speaker.wave.2", "F"),
        A("edge.find", "Find on Page", ("F", "cmd"), "Ctrl+F", "magnifyingglass", "F"),
    ])

# ================================================================ media
app("spotify", "Spotify", ["com.spotify.client"], "Spotify.exe", SPOTIFY,
    "com.spotify.client is the documented identifier (not installed here). Spotify's page writes 'Alt' for the Mac Option key. Its current list has no "
    "next/previous-track or volume shortcuts (Up/Down arrows move through lists), so those aren't included. Space only toggles playback when no text "
    "field has focus.",
    [
        A("spotify.playPause", "Play / Pause", ("Space", ""), "Space", "playpause.fill", "R"),
        A("spotify.like", "Like / Unlike Song", ("B", "opt shift"), "Alt+Shift+B", "heart", "R"),
        A("spotify.shuffle", "Shuffle", ("S", "opt"), "Ctrl+S", "shuffle", "R"),
        A("spotify.repeat", "Repeat", ("R", "opt"), "Ctrl+R", "repeat", "R"),
        A("spotify.mute", "Mute / Unmute", ("M", ""), "M", "speaker.slash", "R"),
        A("spotify.search", "Search", ("K", "cmd"), "Ctrl+K", "magnifyingglass", "F"),
        A("spotify.nowPlaying", "Now Playing", ("J", "opt shift"), "Alt+Shift+J", "music.note", "F"),
        A("spotify.queue", "Queue", ("Q", "opt shift"), "Alt+Shift+Q", "list.bullet", "F"),
        A("spotify.likedSongs", "Liked Songs", ("S", "opt shift"), "Alt+Shift+S", "heart.circle", "F"),
    ])

app("music", "Apple Music", ["com.apple.Music"], "AppleMusic.exe", MUSIC,
    "Bundle ID verified on this Mac (1.7.2). Windows column is Apple's Apple Music for Windows guide; AppleMusic.exe is not verified on a "
    "Windows PC. Left/Right arrow skip only while a song is playing from a list.",
    [
        A("music.playPause", "Play / Pause", ("Space", ""), "Ctrl+Space", "playpause.fill", "R"),
        A("music.next", "Next Song", ("→", ""), "Ctrl+→", "forward.fill", "R"),
        A("music.previous", "Previous Song", ("←", ""), "Ctrl+←", "backward.fill", "R"),
        A("music.volumeUp", "Volume Up", ("↑", "cmd"), "Ctrl+↑", "speaker.wave.3.fill", "R"),
        A("music.volumeDown", "Volume Down", ("↓", "cmd"), "Ctrl+↓", "speaker.wave.1.fill", "R"),
        A("music.stop", "Stop", (".", "cmd"), "Ctrl+.", "stop.fill", "R"),
        A("music.currentSong", "Show Current Song", ("L", "cmd"), "Ctrl+L", "music.note", "F"),
        A("music.queue", "Show Queue", ("U", "opt cmd"), None, "list.bullet", "F", "No Windows shortcut listed."),
        A("music.miniPlayer", "MiniPlayer", ("M", "opt cmd"), "Shift+Ctrl+M", "rectangle.inset.topright.filled", "F", "Mac: ⇧⌘M also works."),
        A("music.fullScreen", "Full Screen Player", ("F", "shift cmd"), "Shift+Ctrl+F", "arrow.up.left.and.arrow.down.right", "F"),
        A("music.search", "Search", ("F", "cmd"), None, "magnifyingglass", "F",
          "Windows uses access keys pressed in sequence (Alt, then N, F), which a single combo can't send."),
    ], windowsSource=MUSIC_WIN)

# ================================================================ Apple apps
app("finder", "Finder", ["com.apple.finder"], None, FINDER,
    "Bundle ID verified on this Mac (/System/Library/CoreServices/Finder.app). Mac only.",
    [
        A("finder.newWindow", "New Finder Window", ("N", "cmd"), None, "macwindow", "F"),
        A("finder.newFolder", "New Folder", ("N", "shift cmd"), None, "folder.badge.plus", "F"),
        A("finder.goToFolder", "Go to Folder", ("G", "shift cmd"), None, "folder", "F"),
        A("finder.downloads", "Downloads", ("L", "opt cmd"), None, "arrow.down.circle", "F"),
        A("finder.desktop", "Desktop", ("D", "shift cmd"), None, "desktopcomputer", "F"),
        A("finder.home", "Home", ("H", "shift cmd"), None, "house", "F"),
        A("finder.documents", "Documents", ("O", "shift cmd"), None, "doc", "F"),
        A("finder.airdrop", "AirDrop", ("R", "shift cmd"), None, "airplayaudio", "F"),
        A("finder.connect", "Connect to Server", ("K", "cmd"), None, "network", "F"),
        A("finder.getInfo", "Get Info", ("I", "cmd"), None, "info.circle", "F"),
        A("finder.quickLook", "Quick Look", ("Y", "cmd"), None, "eye", "F", "Space bar also works."),
        A("finder.trash", "Move to Trash", ("Delete", "cmd"), None, "trash", "F"),
    ])

app("mail", "Mail", ["com.apple.mail"], None, MAIL,
    "Bundle ID verified on this Mac. Mac only.",
    [
        A("mail.new", "New Email", ("N", "cmd"), None, "square.and.pencil", "F"),
        A("mail.getMail", "Get New Mail", ("N", "shift cmd"), None, "tray.and.arrow.down", "F"),
        A("mail.send", "Send", ("D", "shift cmd"), None, "paperplane", "F"),
        A("mail.reply", "Reply", ("R", "cmd"), None, "arrowshape.turn.up.left", "F"),
        A("mail.replyAll", "Reply All", ("R", "shift cmd"), None, "arrowshape.turn.up.left.2", "F"),
        A("mail.forward", "Forward", ("F", "shift cmd"), None, "arrowshape.turn.up.right", "F"),
        A("mail.archive", "Archive", ("A", "ctrl cmd"), None, "archivebox", "F"),
        A("mail.markRead", "Mark Read / Unread", ("U", "shift cmd"), None, "envelope.open", "F"),
        A("mail.junk", "Move to Junk", ("J", "shift cmd"), None, "xmark.bin", "F"),
        A("mail.movePredicted", "Move to Predicted Mailbox", ("M", "ctrl cmd"), None, "folder", "F"),
        A("mail.filter", "Filter Mailbox", ("L", "cmd"), None, "line.3.horizontal.decrease.circle", "F"),
        A("mail.sidebar", "Show / Hide Sidebar", ("S", "ctrl cmd"), None, "sidebar.left", "F"),
    ])

app("notes", "Notes", ["com.apple.Notes"], None, NOTES,
    "Bundle ID verified on this Mac (4.13). Mac only. Quick Note (Fn-Q) needs the Fn key, so it isn't included.",
    [
        A("notes.new", "New Note", ("N", "cmd"), None, "square.and.pencil", "F"),
        A("notes.newFolder", "New Folder", ("N", "shift cmd"), None, "folder.badge.plus", "F"),
        A("notes.search", "Search All Notes", ("F", "opt cmd"), None, "magnifyingglass", "F"),
        A("notes.checklist", "Checklist", ("L", "shift cmd"), None, "checklist", "F"),
        A("notes.checkItem", "Check / Uncheck Item", ("U", "shift cmd"), None, "checkmark.square", "F"),
        A("notes.table", "Insert Table", ("T", "opt cmd"), None, "tablecells", "F"),
        A("notes.title", "Title Format", ("T", "shift cmd"), None, "textformat.size", "F"),
        A("notes.heading", "Heading Format", ("H", "shift cmd"), None, "textformat", "F"),
        A("notes.bullets", "Bulleted List", ("7", "shift cmd"), None, "list.bullet", "F"),
        A("notes.attach", "Attach File", ("A", "shift cmd"), None, "paperclip", "F"),
        A("notes.sidebar", "Show / Hide Sidebar", ("S", "ctrl cmd"), None, "sidebar.left", "F"),
        A("notes.duplicate", "Duplicate Note", ("D", "cmd"), None, "plus.square.on.square", "F"),
    ])

# ================================================================ checks
ids = set()
for a in APPS:
    for x in a["actions"]:
        assert x["id"] not in ids, x["id"]; ids.add(x["id"])
    n = sum(1 for x in a["actions"] if x["swift"])
    assert n <= 12, (a["name"], n)

# ================================================================ JSON
out = []
for a in APPS:
    acts = []
    for x in a["actions"]:
        d = dict(id=x["id"], title=x["title"], mac=mac_display(x["mac"]), windows=x["win"], notes=x["notes"],
                 source=x["source"] or a["source"])
        ws = x["windowsSource"] or a["windowsSource"]
        if ws and x["win"] is not None and not x["source"]: d["windowsSource"] = ws
        acts.append(d)
    out.append(dict(app=a["name"], macBundleIDs=a["ids"], windowsProcess=a["win"], notes=a["notes"], actions=acts))
with open(JSON_OUT, "w") as f:
    json.dump(out, f, ensure_ascii=False, indent=2); f.write("\n")

# ================================================================ Swift
def s(v): return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
L = []
L.append("import Foundation")
L.append("")
L.append("// Curated in-app shortcuts, each from the app maker's own documentation (see `source`).")
L.append("// Generated with docs/app-actions.json, which also has the Windows keys, notes, and actions with no")
L.append("// default shortcut (e.g. Teams meeting reactions).")
L.append("")
L.append("extension AppActionPresets {")
L.append("    static let catalog: [AppActionPreset] = [")
for a in APPS:
    if any(x["swift"] for x in a["actions"]): L.append(f"        {a['key']},")
L.append("    ].flatMap { $0 }")
for a in APPS:
    sw = [x for x in a["actions"] if x["swift"]]
    if not sw: continue
    L.append("")
    L.append(f"    // MARK: {a['name']}")
    L.append("")
    L.append(f"    private static let {a['key']}: [AppActionPreset] = {{")
    L.append(f"        let app = {s(a['name'])}")
    L.append(f"        let ids = [{', '.join(s(i) for i in a['ids'])}]")
    uses_doc = any(not x["source"] or x["source"] == a["source"] for x in sw)
    if uses_doc: L.append(f"        let doc = {s(a['source'])}")
    L.append("        return [")
    for x in sw:
        dl = ".bringToFrontAndReturn" if x["delivery"] == "R" else ".bringToFront"
        src = "doc" if (not x["source"] or x["source"] == a["source"]) else s(x["source"])
        L.append(f"            AppActionPreset(id: {s(x['id'])}, appName: app, bundleIDs: ids, title: {s(x['title'])},")
        L.append(f"                            symbol: {s(x['symbol'])}, combo: {swift_combo(x['mac'])},")
        L.append(f"                            delivery: {dl}, source: {src}),")
    L.append("        ]")
    L.append("    }()")
L.append("}")
with open(SWIFT_OUT, "w") as f:
    f.write("\n".join(L) + "\n")

syms = sorted({x["symbol"] for a in APPS for x in a["actions"] if x["swift"]})
labels = sorted({x["mac"][0] for a in APPS for x in a["actions"] if x["swift"]})
open(SYMBOLS_OUT, "w").write("\n".join(syms))
print("apps", len(APPS), "actions", sum(len(a["actions"]) for a in APPS), "swift presets", sum(1 for a in APPS for x in a["actions"] if x["swift"]))
print("labels", labels)
