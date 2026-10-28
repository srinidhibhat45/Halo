import Foundation

// Curated in-app shortcuts, each from the app maker's own documentation (see `source`).
// Generated with docs/app-actions.json, which also has the Windows keys, notes, and actions with no
// default shortcut (e.g. Teams meeting reactions).

extension AppActionPresets {
    static let catalog: [AppActionPreset] = [
        teams,
        zoom,
        meet,
        slack,
        webex,
        facetime,
        discord,
        outlook,
        word,
        excel,
        powerpoint,
        keynote,
        notion,
        figma,
        photoshop,
        lightroom,
        premiere,
        finalcut,
        resolve,
        vscode,
        xcode,
        chrome,
        safari,
        arc,
        edge,
        spotify,
        music,
        finder,
        mail,
        notes,
    ].flatMap { $0 }

    // MARK: Microsoft Teams

    private static let teams: [AppActionPreset] = {
        let app = "Microsoft Teams"
        let ids = ["com.microsoft.teams2", "com.microsoft.teams"]
        let doc = "https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2"
        return [
            AppActionPreset(id: "teams.mute", appName: app, bundleIDs: ids, title: "Mute / Unmute",
                            symbol: "mic.slash.fill", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.camera", appName: app, bundleIDs: ids, title: "Camera On / Off",
                            symbol: "video.slash.fill", combo: keys("O", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.raiseHand", appName: app, bundleIDs: ids, title: "Raise / Lower Hand",
                            symbol: "hand.raised.fill", combo: keys("K", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.share", appName: app, bundleIDs: ids, title: "Share Content",
                            symbol: "rectangle.on.rectangle", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "teams.hangUp", appName: app, bundleIDs: ids, title: "Hang Up",
                            symbol: "phone.down.fill", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.captions", appName: app, bundleIDs: ids, title: "Live Captions",
                            symbol: "captions.bubble", combo: keys("A", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.acceptAudio", appName: app, bundleIDs: ids, title: "Accept Audio Call",
                            symbol: "phone.fill", combo: keys("A", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.acceptVideo", appName: app, bundleIDs: ids, title: "Accept Video Call",
                            symbol: "video.fill", combo: keys("V", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "teams.decline", appName: app, bundleIDs: ids, title: "Decline Call",
                            symbol: "phone.down.circle.fill", combo: keys("D", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "teams.admitLobby", appName: app, bundleIDs: ids, title: "Admit from Lobby",
                            symbol: "person.badge.plus", combo: keys("Y", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
        ]
    }()

    // MARK: Zoom Workplace

    private static let zoom: [AppActionPreset] = {
        let app = "Zoom Workplace"
        let ids = ["us.zoom.xos"]
        let doc = "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050"
        return [
            AppActionPreset(id: "zoom.mute", appName: app, bundleIDs: ids, title: "Mute / Unmute",
                            symbol: "mic.slash.fill", combo: keys("A", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "zoom.camera", appName: app, bundleIDs: ids, title: "Camera On / Off",
                            symbol: "video.slash.fill", combo: keys("V", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "zoom.raiseHand", appName: app, bundleIDs: ids, title: "Raise / Lower Hand",
                            symbol: "hand.raised.fill", combo: keys("Y", [.option]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "zoom.share", appName: app, bundleIDs: ids, title: "Start / Stop Share",
                            symbol: "rectangle.on.rectangle", combo: keys("S", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "zoom.chat", appName: app, bundleIDs: ids, title: "Show / Hide Chat",
                            symbol: "message", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "zoom.participants", appName: app, bundleIDs: ids, title: "Show / Hide Participants",
                            symbol: "person.2", combo: keys("U", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "zoom.reactionsPanel", appName: app, bundleIDs: ids, title: "Reactions Panel",
                            symbol: "face.smiling", combo: keys("Y", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "zoom.thumbsUp", appName: app, bundleIDs: ids, title: "React: Thumbs Up",
                            symbol: "hand.thumbsup.fill", combo: keys("5", [.option, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "zoom.clap", appName: app, bundleIDs: ids, title: "React: Clap",
                            symbol: "hands.clap.fill", combo: keys("4", [.option, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "zoom.leave", appName: app, bundleIDs: ids, title: "Leave Meeting",
                            symbol: "phone.down.fill", combo: keys("W", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "zoom.answerCall", appName: app, bundleIDs: ids, title: "Answer Call (Zoom Phone)",
                            symbol: "phone.fill", combo: keys("A", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "zoom.declineCall", appName: app, bundleIDs: ids, title: "Decline Call (Zoom Phone)",
                            symbol: "phone.down.circle.fill", combo: keys("D", [.control, .shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
        ]
    }()

    // MARK: Google Meet

    private static let meet: [AppActionPreset] = {
        let app = "Google Meet"
        let ids = ["com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan", "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox"]
        let doc = "https://support.google.com/a/users/answer/9896256?hl=en&co=GENIE.Platform%3DDesktop"
        return [
            AppActionPreset(id: "meet.mute", appName: app, bundleIDs: ids, title: "Mute / Unmute",
                            symbol: "mic.slash.fill", combo: keys("D", [.command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "meet.camera", appName: app, bundleIDs: ids, title: "Camera On / Off",
                            symbol: "video.slash.fill", combo: keys("E", [.command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "meet.raiseHand", appName: app, bundleIDs: ids, title: "Raise / Lower Hand",
                            symbol: "hand.raised.fill", combo: keys("H", [.control, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "meet.chat", appName: app, bundleIDs: ids, title: "Show / Hide Chat",
                            symbol: "message", combo: keys("C", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "meet.participants", appName: app, bundleIDs: ids, title: "Show / Hide People",
                            symbol: "person.2", combo: keys("P", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "meet.captions", appName: app, bundleIDs: ids, title: "Captions On / Off",
                            symbol: "captions.bubble", combo: keys("C", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "meet.present", appName: app, bundleIDs: ids, title: "Start Presenting",
                            symbol: "rectangle.on.rectangle", combo: keys("T", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "meet.pip", appName: app, bundleIDs: ids, title: "Picture-in-Picture",
                            symbol: "pip.enter", combo: keys("M", [.shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
        ]
    }()

    // MARK: Slack

    private static let slack: [AppActionPreset] = {
        let app = "Slack"
        let ids = ["com.tinyspeck.slackmacgap"]
        let doc = "https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts"
        return [
            AppActionPreset(id: "slack.huddle", appName: app, bundleIDs: ids, title: "Start / Join / Leave Huddle",
                            symbol: "headphones", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "slack.huddleMute", appName: app, bundleIDs: ids, title: "Huddle Mute / Unmute",
                            symbol: "mic.slash.fill", combo: keys("Space", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "slack.search", appName: app, bundleIDs: ids, title: "Search",
                            symbol: "magnifyingglass", combo: keys("G", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.newMessage", appName: app, bundleIDs: ids, title: "New Message",
                            symbol: "square.and.pencil", combo: keys("N", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.unreads", appName: app, bundleIDs: ids, title: "All Unreads",
                            symbol: "tray.full", combo: keys("A", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.threads", appName: app, bundleIDs: ids, title: "Threads",
                            symbol: "bubble.left.and.bubble.right", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.activity", appName: app, bundleIDs: ids, title: "Activity",
                            symbol: "bell", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.dms", appName: app, bundleIDs: ids, title: "Browse DMs",
                            symbol: "message", combo: keys("K", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.status", appName: app, bundleIDs: ids, title: "Set Status",
                            symbol: "person.crop.circle", combo: keys("Y", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "slack.markAllRead", appName: app, bundleIDs: ids, title: "Mark All as Read",
                            symbol: "checkmark.circle", combo: keys("Esc", [.shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "slack.nextUnread", appName: app, bundleIDs: ids, title: "Next Unread Conversation",
                            symbol: "arrow.down.circle", combo: keys("↓", [.option, .shift]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Webex

    private static let webex: [AppActionPreset] = {
        let app = "Webex"
        let ids = ["Cisco-Systems.Spark"]
        let doc = "https://help.webex.com/en-us/article/7wr87q/Webex-App-%7C-Keyboard-navigation-and-shortcuts"
        return [
            AppActionPreset(id: "webex.mute", appName: app, bundleIDs: ids, title: "Mute / Unmute",
                            symbol: "mic.slash.fill", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.camera", appName: app, bundleIDs: ids, title: "Camera On / Off",
                            symbol: "video.slash.fill", combo: keys("V", [.control, .shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.raiseHand", appName: app, bundleIDs: ids, title: "Raise / Lower Hand",
                            symbol: "hand.raised.fill", combo: keys("R", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.share", appName: app, bundleIDs: ids, title: "Share Content",
                            symbol: "rectangle.on.rectangle", combo: keys("D", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "webex.stopShare", appName: app, bundleIDs: ids, title: "Stop Sharing",
                            symbol: "rectangle.on.rectangle.slash", combo: keys("Z", [.control, .shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.chat", appName: app, bundleIDs: ids, title: "Open / Close Chat",
                            symbol: "message", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "webex.captions", appName: app, bundleIDs: ids, title: "Closed Captions On / Off",
                            symbol: "captions.bubble", combo: keys("A", [.control, .shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.reactionsPanel", appName: app, bundleIDs: ids, title: "Reactions Panel",
                            symbol: "face.smiling", combo: keys("Y", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "webex.thumbsUp", appName: app, bundleIDs: ids, title: "React: Thumbs Up",
                            symbol: "hand.thumbsup.fill", combo: keys("4", [.option, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.endCall", appName: app, bundleIDs: ids, title: "End Call",
                            symbol: "phone.down.fill", combo: keys("L", [.command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "webex.answer", appName: app, bundleIDs: ids, title: "Answer Call",
                            symbol: "phone.fill", combo: keys("C", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "webex.decline", appName: app, bundleIDs: ids, title: "Decline Call",
                            symbol: "phone.down.circle.fill", combo: keys("D", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
        ]
    }()

    // MARK: FaceTime

    private static let facetime: [AppActionPreset] = {
        let app = "FaceTime"
        let ids = ["com.apple.FaceTime"]
        let doc = "https://support.apple.com/guide/facetime/keyboard-shortcuts-fctma3b7b94b/mac"
        return [
            AppActionPreset(id: "facetime.fullScreen", appName: app, bundleIDs: ids, title: "Full Screen",
                            symbol: "arrow.up.left.and.arrow.down.right", combo: keys("F", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "facetime.rotate", appName: app, bundleIDs: ids, title: "Landscape / Portrait",
                            symbol: "rectangle.portrait.rotate", combo: keys("R", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "facetime.close", appName: app, bundleIDs: ids, title: "Close FaceTime Window",
                            symbol: "xmark.square", combo: keys("W", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Discord

    private static let discord: [AppActionPreset] = {
        let app = "Discord"
        let ids = ["com.hnc.Discord"]
        let doc = "https://discord.com/blog/how-to-use-keyboard-shortcuts-on-discord-create-custom-keybinds"
        return [
            AppActionPreset(id: "discord.mute", appName: app, bundleIDs: ids, title: "Mute / Unmute",
                            symbol: "mic.slash.fill", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "discord.deafen", appName: app, bundleIDs: ids, title: "Deafen / Undeafen",
                            symbol: "speaker.slash.fill", combo: keys("D", [.shift, .command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "discord.answer", appName: app, bundleIDs: ids, title: "Answer Call",
                            symbol: "phone.fill", combo: keys("Return", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "discord.decline", appName: app, bundleIDs: ids, title: "Decline Call",
                            symbol: "phone.down.fill", combo: keys("Esc", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "discord.currentCall", appName: app, bundleIDs: ids, title: "Jump to Current Call",
                            symbol: "arrowshape.turn.up.right.circle", combo: keys("V", [.option, .shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "discord.soundboard", appName: app, bundleIDs: ids, title: "Soundboard",
                            symbol: "speaker.wave.2", combo: keys("B", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "discord.quickSwitcher", appName: app, bundleIDs: ids, title: "Quick Switcher",
                            symbol: "magnifyingglass", combo: keys("K", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "discord.emoji", appName: app, bundleIDs: ids, title: "Emoji Picker",
                            symbol: "face.smiling", combo: keys("E", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "discord.upload", appName: app, bundleIDs: ids, title: "Attach File",
                            symbol: "paperclip", combo: keys("U", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "discord.shortcuts", appName: app, bundleIDs: ids, title: "Show Shortcuts",
                            symbol: "keyboard", combo: keys("/", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Microsoft Outlook

    private static let outlook: [AppActionPreset] = {
        let app = "Microsoft Outlook"
        let ids = ["com.microsoft.Outlook"]
        let doc = "https://support.microsoft.com/en-us/accessibility/outlook/mac/keyboard-shortcuts-in-outlook-for-mac"
        return [
            AppActionPreset(id: "outlook.newMessage", appName: app, bundleIDs: ids, title: "New Message",
                            symbol: "square.and.pencil", combo: keys("N", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.reply", appName: app, bundleIDs: ids, title: "Reply",
                            symbol: "arrowshape.turn.up.left", combo: keys("R", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.replyAll", appName: app, bundleIDs: ids, title: "Reply All",
                            symbol: "arrowshape.turn.up.left.2", combo: keys("R", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.forward", appName: app, bundleIDs: ids, title: "Forward",
                            symbol: "arrowshape.turn.up.right", combo: keys("J", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.archive", appName: app, bundleIDs: ids, title: "Archive",
                            symbol: "archivebox", combo: keys("E", [.control]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.markRead", appName: app, bundleIDs: ids, title: "Mark as Read",
                            symbol: "envelope.open", combo: keys("T", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.markUnread", appName: app, bundleIDs: ids, title: "Mark as Unread",
                            symbol: "envelope.badge", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.flag", appName: app, bundleIDs: ids, title: "Flag for Follow Up",
                            symbol: "flag", combo: keys("=", [.control]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.move", appName: app, bundleIDs: ids, title: "Move to Folder",
                            symbol: "folder", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.mail", appName: app, bundleIDs: ids, title: "Go to Mail",
                            symbol: "envelope", combo: keys("1", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.calendar", appName: app, bundleIDs: ids, title: "Go to Calendar",
                            symbol: "calendar", combo: keys("2", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "outlook.sync", appName: app, bundleIDs: ids, title: "Send & Receive",
                            symbol: "arrow.clockwise", combo: keys("K", [.control, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Microsoft Word

    private static let word: [AppActionPreset] = {
        let app = "Microsoft Word"
        let ids = ["com.microsoft.Word"]
        let doc = "https://support.microsoft.com/en-us/accessibility/word/keyboard-shortcuts-in-word"
        return [
            AppActionPreset(id: "word.save", appName: app, bundleIDs: ids, title: "Save",
                            symbol: "square.and.arrow.down", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: "https://support.microsoft.com/en-us/office/common-office-for-mac-keyboard-shortcuts-307f469a-1a05-4263-9b55-49df19a8b8ff"),
            AppActionPreset(id: "word.trackChanges", appName: app, bundleIDs: ids, title: "Track Changes On / Off",
                            symbol: "text.badge.checkmark", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.comment", appName: app, bundleIDs: ids, title: "New Comment",
                            symbol: "text.bubble", combo: keys("A", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.find", appName: app, bundleIDs: ids, title: "Find",
                            symbol: "magnifyingglass", combo: keys("F", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.replace", appName: app, bundleIDs: ids, title: "Find & Replace",
                            symbol: "magnifyingglass", combo: keys("H", [.control]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.spelling", appName: app, bundleIDs: ids, title: "Spelling & Grammar",
                            symbol: "textformat.abc", combo: keys("L", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.pageBreak", appName: app, bundleIDs: ids, title: "Page Break",
                            symbol: "doc.badge.plus", combo: keys("Return", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.heading1", appName: app, bundleIDs: ids, title: "Heading 1",
                            symbol: "textformat.size", combo: keys("1", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "word.print", appName: app, bundleIDs: ids, title: "Print",
                            symbol: "printer", combo: keys("P", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Microsoft Excel

    private static let excel: [AppActionPreset] = {
        let app = "Microsoft Excel"
        let ids = ["com.microsoft.Excel"]
        let doc = "https://support.microsoft.com/en-us/accessibility/excel/keyboard-shortcuts-in-excel"
        return [
            AppActionPreset(id: "excel.save", appName: app, bundleIDs: ids, title: "Save",
                            symbol: "square.and.arrow.down", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.autoSum", appName: app, bundleIDs: ids, title: "AutoSum",
                            symbol: "sum", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.filter", appName: app, bundleIDs: ids, title: "Filter On / Off",
                            symbol: "line.3.horizontal.decrease.circle", combo: keys("F", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.formatCells", appName: app, bundleIDs: ids, title: "Format Cells",
                            symbol: "tablecells", combo: keys("1", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.fillDown", appName: app, bundleIDs: ids, title: "Fill Down",
                            symbol: "arrow.down.to.line", combo: keys("D", [.control]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.insertCells", appName: app, bundleIDs: ids, title: "Insert Cells",
                            symbol: "plus.square", combo: keys("=", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.deleteCells", appName: app, bundleIDs: ids, title: "Delete Cells",
                            symbol: "minus.square", combo: keys("-", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.note", appName: app, bundleIDs: ids, title: "New Note",
                            symbol: "note.text", combo: keys("F2", [.shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.comment", appName: app, bundleIDs: ids, title: "New Threaded Comment",
                            symbol: "text.bubble", combo: keys("F2", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.pasteSpecial", appName: app, bundleIDs: ids, title: "Paste Special",
                            symbol: "doc.on.clipboard", combo: keys("V", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "excel.calculate", appName: app, bundleIDs: ids, title: "Calculate Now",
                            symbol: "function", combo: keys("=", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Microsoft PowerPoint

    private static let powerpoint: [AppActionPreset] = {
        let app = "Microsoft PowerPoint"
        let ids = ["com.microsoft.Powerpoint"]
        let doc = "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-deliver-powerpoint-presentations"
        return [
            AppActionPreset(id: "ppt.playFromStart", appName: app, bundleIDs: ids, title: "Play from Start",
                            symbol: "play.fill", combo: keys("Return", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.playFromCurrent", appName: app, bundleIDs: ids, title: "Play from Current Slide",
                            symbol: "play", combo: keys("Return", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.presenterView", appName: app, bundleIDs: ids, title: "Presenter View",
                            symbol: "play.rectangle", combo: keys("Return", [.option]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.next", appName: app, bundleIDs: ids, title: "Next Slide",
                            symbol: "chevron.right", combo: keys("→", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.previous", appName: app, bundleIDs: ids, title: "Previous Slide",
                            symbol: "chevron.left", combo: keys("←", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.black", appName: app, bundleIDs: ids, title: "Black Screen",
                            symbol: "rectangle.fill", combo: keys("B", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.white", appName: app, bundleIDs: ids, title: "White Screen",
                            symbol: "rectangle", combo: keys("W", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.laser", appName: app, bundleIDs: ids, title: "Laser Pointer",
                            symbol: "laser.burst", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.end", appName: app, bundleIDs: ids, title: "End Slide Show",
                            symbol: "xmark.circle", combo: keys("Esc", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ppt.newSlide", appName: app, bundleIDs: ids, title: "New Slide",
                            symbol: "rectangle.badge.plus", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-create-powerpoint-presentations"),
            AppActionPreset(id: "ppt.comment", appName: app, bundleIDs: ids, title: "New Comment",
                            symbol: "text.bubble", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFront, source: "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-create-powerpoint-presentations"),
            AppActionPreset(id: "ppt.save", appName: app, bundleIDs: ids, title: "Save",
                            symbol: "square.and.arrow.down", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-create-powerpoint-presentations"),
        ]
    }()

    // MARK: Keynote

    private static let keynote: [AppActionPreset] = {
        let app = "Keynote"
        let ids = ["com.apple.iWork.Keynote"]
        let doc = "https://support.apple.com/guide/keynote/keyboard-shortcuts-tanfde4a3e6d/mac"
        return [
            AppActionPreset(id: "keynote.play", appName: app, bundleIDs: ids, title: "Play Slideshow",
                            symbol: "play.fill", combo: keys("P", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.next", appName: app, bundleIDs: ids, title: "Next Slide / Build",
                            symbol: "chevron.right", combo: keys("→", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.previous", appName: app, bundleIDs: ids, title: "Previous Slide",
                            symbol: "chevron.left", combo: keys("←", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.notes", appName: app, bundleIDs: ids, title: "Show / Hide Presenter Notes",
                            symbol: "note.text", combo: keys("P", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.black", appName: app, bundleIDs: ids, title: "Black Screen",
                            symbol: "rectangle.fill", combo: keys("B", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.white", appName: app, bundleIDs: ids, title: "White Screen",
                            symbol: "rectangle", combo: keys("W", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.stop", appName: app, bundleIDs: ids, title: "Quit Presentation",
                            symbol: "xmark.circle", combo: keys("Esc", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.newSlide", appName: app, bundleIDs: ids, title: "New Slide",
                            symbol: "rectangle.badge.plus", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.skip", appName: app, bundleIDs: ids, title: "Skip / Unskip Slide",
                            symbol: "eye.slash", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "keynote.save", appName: app, bundleIDs: ids, title: "Save",
                            symbol: "square.and.arrow.down", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Notion

    private static let notion: [AppActionPreset] = {
        let app = "Notion"
        let ids = ["notion.id"]
        let doc = "https://www.notion.com/help/keyboard-shortcuts"
        return [
            AppActionPreset(id: "notion.search", appName: app, bundleIDs: ids, title: "Search",
                            symbol: "magnifyingglass", combo: keys("P", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.newPage", appName: app, bundleIDs: ids, title: "New Page",
                            symbol: "square.and.pencil", combo: keys("N", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.newTab", appName: app, bundleIDs: ids, title: "New Tab",
                            symbol: "plus.rectangle.on.rectangle", combo: keys("T", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.newWindow", appName: app, bundleIDs: ids, title: "New Window",
                            symbol: "macwindow", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.copyLink", appName: app, bundleIDs: ids, title: "Copy Page Link",
                            symbol: "link", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.back", appName: app, bundleIDs: ids, title: "Back",
                            symbol: "arrow.left", combo: keys("[", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.forward", appName: app, bundleIDs: ids, title: "Forward",
                            symbol: "arrow.right", combo: keys("]", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.darkMode", appName: app, bundleIDs: ids, title: "Dark / Light Mode",
                            symbol: "circle.lefthalf.filled", combo: keys("L", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notion.comment", appName: app, bundleIDs: ids, title: "New Comment",
                            symbol: "text.bubble", combo: keys("M", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Figma

    private static let figma: [AppActionPreset] = {
        let app = "Figma"
        let ids = ["com.figma.Desktop"]
        let doc = "https://help.figma.com/hc/en-us/articles/360040328653-Use-Figma-products-with-a-keyboard"
        return [
            AppActionPreset(id: "figma.actions", appName: app, bundleIDs: ids, title: "Actions Menu",
                            symbol: "command", combo: keys("K", [.command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/23570416033943-Use-the-actions-menu-in-Figma-Design"),
            AppActionPreset(id: "figma.createComponent", appName: app, bundleIDs: ids, title: "Create Component",
                            symbol: "square.on.square", combo: keys("K", [.option, .command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360038663154-Create-components-to-reuse-in-designs"),
            AppActionPreset(id: "figma.frameSelection", appName: app, bundleIDs: ids, title: "Frame Selection",
                            symbol: "square.dashed", combo: keys("G", [.option, .command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design"),
            AppActionPreset(id: "figma.ungroup", appName: app, bundleIDs: ids, title: "Ungroup / Unframe",
                            symbol: "square.3.layers.3d", combo: keys("G", [.shift, .command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design"),
            AppActionPreset(id: "figma.duplicate", appName: app, bundleIDs: ids, title: "Duplicate",
                            symbol: "plus.square.on.square", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design"),
            AppActionPreset(id: "figma.resizeToFit", appName: app, bundleIDs: ids, title: "Resize Frame to Fit",
                            symbol: "rectangle.compress.vertical", combo: keys("R", [.option, .shift, .command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design"),
            AppActionPreset(id: "figma.autoLayout", appName: app, bundleIDs: ids, title: "Add Auto Layout",
                            symbol: "rectangle.split.2x1", combo: keys("A", [.shift]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout-in-Figma"),
            AppActionPreset(id: "figma.removeAutoLayout", appName: app, bundleIDs: ids, title: "Remove Auto Layout",
                            symbol: "rectangle", combo: keys("A", [.option, .shift]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout-in-Figma"),
            AppActionPreset(id: "figma.export", appName: app, bundleIDs: ids, title: "Export",
                            symbol: "square.and.arrow.up", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: "https://help.figma.com/hc/en-us/articles/360040028114-Export-static-designs-from-Figma"),
            AppActionPreset(id: "figma.shortcuts", appName: app, bundleIDs: ids, title: "Keyboard Shortcuts Panel",
                            symbol: "keyboard", combo: keys("/", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Adobe Photoshop

    private static let photoshop: [AppActionPreset] = {
        let app = "Adobe Photoshop"
        let ids = ["com.adobe.Photoshop"]
        let doc = "https://helpx.adobe.com/content/dam/help/en/photoshop/using/default-keyboard-shortcuts/photoshop-keyboard-shortcuts.pdf"
        return [
            AppActionPreset(id: "ps.brush", appName: app, bundleIDs: ids, title: "Brush Tool",
                            symbol: "paintbrush.fill", combo: keys("B", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.eraser", appName: app, bundleIDs: ids, title: "Eraser Tool",
                            symbol: "eraser.fill", combo: keys("E", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.move", appName: app, bundleIDs: ids, title: "Move Tool",
                            symbol: "arrow.up.and.down.and.arrow.left.and.right", combo: keys("V", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.freeTransform", appName: app, bundleIDs: ids, title: "Free Transform",
                            symbol: "skew", combo: keys("T", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.deselect", appName: app, bundleIDs: ids, title: "Deselect",
                            symbol: "square.dashed", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.inverse", appName: app, bundleIDs: ids, title: "Inverse Selection",
                            symbol: "selection.pin.in.out", combo: keys("F7", [.shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.newLayer", appName: app, bundleIDs: ids, title: "New Layer",
                            symbol: "square.3.layers.3d", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.layerViaCopy", appName: app, bundleIDs: ids, title: "New Layer via Copy",
                            symbol: "plus.square.on.square", combo: keys("J", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.mergeVisible", appName: app, bundleIDs: ids, title: "Merge Visible",
                            symbol: "arrow.triangle.merge", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.group", appName: app, bundleIDs: ids, title: "Group Layers",
                            symbol: "folder.badge.plus", combo: keys("G", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.swapColors", appName: app, bundleIDs: ids, title: "Swap Colors",
                            symbol: "arrow.left.arrow.right", combo: keys("X", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "ps.undo", appName: app, bundleIDs: ids, title: "Undo",
                            symbol: "arrow.uturn.backward", combo: keys("Z", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Adobe Lightroom Classic

    private static let lightroom: [AppActionPreset] = {
        let app = "Adobe Lightroom Classic"
        let ids = ["com.adobe.LightroomClassicCC7"]
        let doc = "https://helpx.adobe.com/lightroom-classic/desktop/introduction-to-lightroom-classic/keyboard-shortcuts.html"
        return [
            AppActionPreset(id: "lrc.library", appName: app, bundleIDs: ids, title: "Library Module",
                            symbol: "photo.on.rectangle", combo: keys("1", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.develop", appName: app, bundleIDs: ids, title: "Develop Module",
                            symbol: "slider.horizontal.3", combo: keys("2", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.pick", appName: app, bundleIDs: ids, title: "Flag as Pick",
                            symbol: "flag.fill", combo: keys("P", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.reject", appName: app, bundleIDs: ids, title: "Flag as Reject",
                            symbol: "xmark.bin", combo: keys("X", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.unflag", appName: app, bundleIDs: ids, title: "Unflag",
                            symbol: "flag.slash", combo: keys("U", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.beforeAfter", appName: app, bundleIDs: ids, title: "Before / After",
                            symbol: "rectangle.split.2x1", combo: keys("Y", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.autoTone", appName: app, bundleIDs: ids, title: "Auto Tone",
                            symbol: "wand.and.stars", combo: keys("U", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.copySettings", appName: app, bundleIDs: ids, title: "Copy Develop Settings",
                            symbol: "doc.on.doc", combo: keys("C", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.pasteSettings", appName: app, bundleIDs: ids, title: "Paste Develop Settings",
                            symbol: "doc.on.clipboard", combo: keys("V", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.virtualCopy", appName: app, bundleIDs: ids, title: "Create Virtual Copy",
                            symbol: "plus.square.on.square", combo: keys("'", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.crop", appName: app, bundleIDs: ids, title: "Crop Tool",
                            symbol: "crop", combo: keys("R", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "lrc.export", appName: app, bundleIDs: ids, title: "Export",
                            symbol: "square.and.arrow.up", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Adobe Premiere Pro

    private static let premiere: [AppActionPreset] = {
        let app = "Adobe Premiere Pro"
        let ids = ["com.adobe.PremierePro.26", "com.adobe.PremierePro.25", "com.adobe.PremierePro.24"]
        let doc = "https://helpx.adobe.com/premiere/desktop/get-started/keyboard-shortcuts/default-keyboard-shortcuts.html"
        return [
            AppActionPreset(id: "pr.playStop", appName: app, bundleIDs: ids, title: "Play / Stop",
                            symbol: "play.fill", combo: keys("Space", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.addEdit", appName: app, bundleIDs: ids, title: "Add Edit (Cut at Playhead)",
                            symbol: "scissors", combo: keys("K", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.rippleDelete", appName: app, bundleIDs: ids, title: "Ripple Delete",
                            symbol: "delete.left", combo: keys("Delete", [.option]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.markIn", appName: app, bundleIDs: ids, title: "Mark In",
                            symbol: "arrow.right.to.line", combo: keys("I", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.markOut", appName: app, bundleIDs: ids, title: "Mark Out",
                            symbol: "arrow.left.to.line", combo: keys("O", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.marker", appName: app, bundleIDs: ids, title: "Add Marker",
                            symbol: "bookmark", combo: keys("M", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.snap", appName: app, bundleIDs: ids, title: "Snap On / Off",
                            symbol: "arrow.right.and.line.vertical.and.arrow.left", combo: keys("S", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.transition", appName: app, bundleIDs: ids, title: "Apply Video Transition",
                            symbol: "square.on.square", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.export", appName: app, bundleIDs: ids, title: "Export Media",
                            symbol: "square.and.arrow.up", combo: keys("M", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.undo", appName: app, bundleIDs: ids, title: "Undo",
                            symbol: "arrow.uturn.backward", combo: keys("Z", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.redo", appName: app, bundleIDs: ids, title: "Redo",
                            symbol: "arrow.uturn.forward", combo: keys("Z", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "pr.save", appName: app, bundleIDs: ids, title: "Save",
                            symbol: "square.and.arrow.down", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Final Cut Pro

    private static let finalcut: [AppActionPreset] = {
        let app = "Final Cut Pro"
        let ids = ["com.apple.FinalCut"]
        let doc = "https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac"
        return [
            AppActionPreset(id: "fcp.playPause", appName: app, bundleIDs: ids, title: "Play / Pause",
                            symbol: "play.fill", combo: keys("Space", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.blade", appName: app, bundleIDs: ids, title: "Blade (Cut at Playhead)",
                            symbol: "scissors", combo: keys("B", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.bladeAll", appName: app, bundleIDs: ids, title: "Blade All",
                            symbol: "scissors", combo: keys("B", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.marker", appName: app, bundleIDs: ids, title: "Add Marker",
                            symbol: "bookmark", combo: keys("M", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.rangeStart", appName: app, bundleIDs: ids, title: "Set Range Start",
                            symbol: "arrow.right.to.line", combo: keys("I", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.rangeEnd", appName: app, bundleIDs: ids, title: "Set Range End",
                            symbol: "arrow.left.to.line", combo: keys("O", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.snapping", appName: app, bundleIDs: ids, title: "Snapping On / Off",
                            symbol: "arrow.right.and.line.vertical.and.arrow.left", combo: keys("N", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.skimming", appName: app, bundleIDs: ids, title: "Skimming On / Off",
                            symbol: "waveform", combo: keys("S", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.zoomToFit", appName: app, bundleIDs: ids, title: "Zoom to Fit",
                            symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", combo: keys("Z", [.shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.undo", appName: app, bundleIDs: ids, title: "Undo",
                            symbol: "arrow.uturn.backward", combo: keys("Z", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.share", appName: app, bundleIDs: ids, title: "Share to Default Destination",
                            symbol: "square.and.arrow.up", combo: keys("E", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "fcp.import", appName: app, bundleIDs: ids, title: "Import Media",
                            symbol: "square.and.arrow.down", combo: keys("I", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: DaVinci Resolve

    private static let resolve: [AppActionPreset] = {
        let app = "DaVinci Resolve"
        let ids = ["com.blackmagic-design.DaVinciResolve"]
        let doc = "https://documents.blackmagicdesign.com/UserManuals/DaVinci-Resolve-15-Keyboard-Shortcuts.pdf"
        return [
            AppActionPreset(id: "resolve.playReverse", appName: app, bundleIDs: ids, title: "Play Reverse",
                            symbol: "backward.fill", combo: keys("J", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.stop", appName: app, bundleIDs: ids, title: "Stop",
                            symbol: "stop.fill", combo: keys("K", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.playForward", appName: app, bundleIDs: ids, title: "Play Forward",
                            symbol: "forward.fill", combo: keys("L", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.markIn", appName: app, bundleIDs: ids, title: "Mark In",
                            symbol: "arrow.right.to.line", combo: keys("I", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.markOut", appName: app, bundleIDs: ids, title: "Mark Out",
                            symbol: "arrow.left.to.line", combo: keys("O", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.marker", appName: app, bundleIDs: ids, title: "Add Marker",
                            symbol: "bookmark", combo: keys("M", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.razor", appName: app, bundleIDs: ids, title: "Razor (Cut at Playhead)",
                            symbol: "scissors", combo: keys("B", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.blade", appName: app, bundleIDs: ids, title: "Blade Edit Mode",
                            symbol: "scissors.badge.ellipsis", combo: keys("B", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.snapping", appName: app, bundleIDs: ids, title: "Snapping On / Off",
                            symbol: "arrow.right.and.line.vertical.and.arrow.left", combo: keys("N", []),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.zoomToFit", appName: app, bundleIDs: ids, title: "Zoom to Fit",
                            symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", combo: keys("Z", [.shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.undo", appName: app, bundleIDs: ids, title: "Undo",
                            symbol: "arrow.uturn.backward", combo: keys("Z", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "resolve.save", appName: app, bundleIDs: ids, title: "Save Project",
                            symbol: "square.and.arrow.down", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Visual Studio Code

    private static let vscode: [AppActionPreset] = {
        let app = "Visual Studio Code"
        let ids = ["com.microsoft.VSCode"]
        let doc = "https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf"
        return [
            AppActionPreset(id: "vscode.commandPalette", appName: app, bundleIDs: ids, title: "Command Palette",
                            symbol: "command", combo: keys("P", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.quickOpen", appName: app, bundleIDs: ids, title: "Quick Open File",
                            symbol: "magnifyingglass", combo: keys("P", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.terminal", appName: app, bundleIDs: ids, title: "Show Terminal",
                            symbol: "terminal", combo: keys("`", [.control]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.sidebar", appName: app, bundleIDs: ids, title: "Toggle Sidebar",
                            symbol: "sidebar.left", combo: keys("B", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.explorer", appName: app, bundleIDs: ids, title: "Explorer",
                            symbol: "folder", combo: keys("E", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.search", appName: app, bundleIDs: ids, title: "Search in Files",
                            symbol: "magnifyingglass", combo: keys("F", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.sourceControl", appName: app, bundleIDs: ids, title: "Source Control",
                            symbol: "arrow.triangle.branch", combo: keys("G", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.format", appName: app, bundleIDs: ids, title: "Format Document",
                            symbol: "text.alignleft", combo: keys("F", [.option, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.comment", appName: app, bundleIDs: ids, title: "Toggle Line Comment",
                            symbol: "chevron.left.forwardslash.chevron.right", combo: keys("/", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.split", appName: app, bundleIDs: ids, title: "Split Editor",
                            symbol: "square.split.2x1", combo: keys("\\", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.wordWrap", appName: app, bundleIDs: ids, title: "Toggle Word Wrap",
                            symbol: "text.word.spacing", combo: keys("Z", [.option]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "vscode.debug", appName: app, bundleIDs: ids, title: "Start / Continue Debugging",
                            symbol: "ladybug", combo: keys("F5", []),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Xcode

    private static let xcode: [AppActionPreset] = {
        let app = "Xcode"
        let ids = ["com.apple.dt.Xcode"]
        let doc = "https://developer.apple.com/videos/play/wwdc2024/10181/"
        return [
            AppActionPreset(id: "xcode.build", appName: app, bundleIDs: ids, title: "Build",
                            symbol: "hammer", combo: keys("B", [.command]),
                            delivery: .bringToFront, source: "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"),
            AppActionPreset(id: "xcode.run", appName: app, bundleIDs: ids, title: "Run",
                            symbol: "play.fill", combo: keys("R", [.command]),
                            delivery: .bringToFront, source: "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"),
            AppActionPreset(id: "xcode.stop", appName: app, bundleIDs: ids, title: "Stop",
                            symbol: "stop.fill", combo: keys(".", [.command]),
                            delivery: .bringToFront, source: "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"),
            AppActionPreset(id: "xcode.test", appName: app, bundleIDs: ids, title: "Test",
                            symbol: "checkmark.diamond", combo: keys("U", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "xcode.runWithoutBuilding", appName: app, bundleIDs: ids, title: "Run Without Building",
                            symbol: "play", combo: keys("R", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "xcode.clean", appName: app, bundleIDs: ids, title: "Clean Build Folder",
                            symbol: "trash", combo: keys("K", [.shift, .command]),
                            delivery: .bringToFront, source: "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"),
            AppActionPreset(id: "xcode.openQuickly", appName: app, bundleIDs: ids, title: "Open Quickly",
                            symbol: "magnifyingglass", combo: keys("O", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "xcode.findNavigator", appName: app, bundleIDs: ids, title: "Find in Project",
                            symbol: "text.magnifyingglass", combo: keys("F", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "xcode.quickActions", appName: app, bundleIDs: ids, title: "Quick Actions",
                            symbol: "command", combo: keys("A", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "xcode.debugArea", appName: app, bundleIDs: ids, title: "Show / Hide Debug Area",
                            symbol: "rectangle.bottomthird.inset.filled", combo: keys("Y", [.shift, .command]),
                            delivery: .bringToFront, source: "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"),
            AppActionPreset(id: "xcode.comment", appName: app, bundleIDs: ids, title: "Comment Selection",
                            symbol: "chevron.left.forwardslash.chevron.right", combo: keys("/", [.command]),
                            delivery: .bringToFront, source: "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html"),
        ]
    }()

    // MARK: Google Chrome

    private static let chrome: [AppActionPreset] = {
        let app = "Google Chrome"
        let ids = ["com.google.Chrome"]
        let doc = "https://support.google.com/chrome/answer/157179?hl=en&co=GENIE.Platform%3DDesktop"
        return [
            AppActionPreset(id: "chrome.newTab", appName: app, bundleIDs: ids, title: "New Tab",
                            symbol: "plus.square.on.square", combo: keys("T", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.reopenTab", appName: app, bundleIDs: ids, title: "Reopen Closed Tab",
                            symbol: "arrow.uturn.backward", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.closeTab", appName: app, bundleIDs: ids, title: "Close Tab",
                            symbol: "xmark.square", combo: keys("W", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.nextTab", appName: app, bundleIDs: ids, title: "Next Tab",
                            symbol: "arrow.right.square", combo: keys("→", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.previousTab", appName: app, bundleIDs: ids, title: "Previous Tab",
                            symbol: "arrow.left.square", combo: keys("←", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.incognito", appName: app, bundleIDs: ids, title: "New Incognito Window",
                            symbol: "eyeglasses", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.addressBar", appName: app, bundleIDs: ids, title: "Address Bar",
                            symbol: "link", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.bookmark", appName: app, bundleIDs: ids, title: "Bookmark Page",
                            symbol: "bookmark", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.history", appName: app, bundleIDs: ids, title: "History",
                            symbol: "clock.arrow.circlepath", combo: keys("Y", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.downloads", appName: app, bundleIDs: ids, title: "Downloads",
                            symbol: "arrow.down.circle", combo: keys("J", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.hardReload", appName: app, bundleIDs: ids, title: "Reload (Ignore Cache)",
                            symbol: "arrow.clockwise", combo: keys("R", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "chrome.devTools", appName: app, bundleIDs: ids, title: "Developer Tools",
                            symbol: "chevron.left.forwardslash.chevron.right", combo: keys("I", [.option, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Safari

    private static let safari: [AppActionPreset] = {
        let app = "Safari"
        let ids = ["com.apple.Safari"]
        let doc = "https://support.apple.com/guide/safari/keyboard-shortcuts-and-gestures-cpsh003/mac"
        return [
            AppActionPreset(id: "safari.tabOverview", appName: app, bundleIDs: ids, title: "Tab Overview",
                            symbol: "square.grid.2x2", combo: keys("\\", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.nextTab", appName: app, bundleIDs: ids, title: "Next Tab",
                            symbol: "arrow.right.square", combo: keys("]", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.previousTab", appName: app, bundleIDs: ids, title: "Previous Tab",
                            symbol: "arrow.left.square", combo: keys("[", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.closeTab", appName: app, bundleIDs: ids, title: "Close Tab",
                            symbol: "xmark.square", combo: keys("W", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.reopenTab", appName: app, bundleIDs: ids, title: "Reopen Last Closed Tab",
                            symbol: "arrow.uturn.backward", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.searchField", appName: app, bundleIDs: ids, title: "Smart Search Field",
                            symbol: "link", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.find", appName: app, bundleIDs: ids, title: "Find on Page",
                            symbol: "magnifyingglass", combo: keys("F", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.back", appName: app, bundleIDs: ids, title: "Back",
                            symbol: "arrow.left", combo: keys("[", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.forward", appName: app, bundleIDs: ids, title: "Forward",
                            symbol: "arrow.right", combo: keys("]", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.reader", appName: app, bundleIDs: ids, title: "Reader",
                            symbol: "text.book.closed", combo: keys("R", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.readingList", appName: app, bundleIDs: ids, title: "Add to Reading List",
                            symbol: "eyeglasses", combo: keys("D", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "safari.home", appName: app, bundleIDs: ids, title: "Homepage",
                            symbol: "house", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Arc

    private static let arc: [AppActionPreset] = {
        let app = "Arc"
        let ids = ["company.thebrowser.Browser"]
        let doc = "https://web.archive.org/web/20260725225600/https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts"
        return [
            AppActionPreset(id: "arc.newTab", appName: app, bundleIDs: ids, title: "New Tab",
                            symbol: "plus.square.on.square", combo: keys("T", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.littleArc", appName: app, bundleIDs: ids, title: "Little Arc",
                            symbol: "macwindow", combo: keys("N", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.reopenTab", appName: app, bundleIDs: ids, title: "Reopen Closed Tab",
                            symbol: "arrow.uturn.backward", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.closeTab", appName: app, bundleIDs: ids, title: "Close Tab",
                            symbol: "xmark.square", combo: keys("W", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.pinTab", appName: app, bundleIDs: ids, title: "Pin / Unpin Tab",
                            symbol: "pin", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.copyURL", appName: app, bundleIDs: ids, title: "Copy URL",
                            symbol: "link", combo: keys("C", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.sidebar", appName: app, bundleIDs: ids, title: "Show / Hide Sidebar",
                            symbol: "sidebar.left", combo: keys("S", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.clearTabs", appName: app, bundleIDs: ids, title: "Clear Unpinned Tabs",
                            symbol: "xmark.bin", combo: keys("K", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.splitView", appName: app, bundleIDs: ids, title: "Add Split View",
                            symbol: "rectangle.split.2x1", combo: keys("=", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.closeSplit", appName: app, bundleIDs: ids, title: "Close Split View",
                            symbol: "rectangle", combo: keys("-", [.control, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.nextSpace", appName: app, bundleIDs: ids, title: "Next Space",
                            symbol: "arrow.right.circle", combo: keys("→", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "arc.previousSpace", appName: app, bundleIDs: ids, title: "Previous Space",
                            symbol: "arrow.left.circle", combo: keys("←", [.option, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Microsoft Edge

    private static let edge: [AppActionPreset] = {
        let app = "Microsoft Edge"
        let ids = ["com.microsoft.edgemac"]
        let doc = "https://support.microsoft.com/en-us/edge/keyboard-shortcuts-in-microsoft-edge"
        return [
            AppActionPreset(id: "edge.newTab", appName: app, bundleIDs: ids, title: "New Tab",
                            symbol: "plus.square.on.square", combo: keys("T", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.reopenTab", appName: app, bundleIDs: ids, title: "Reopen Closed Tab",
                            symbol: "arrow.uturn.backward", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.closeTab", appName: app, bundleIDs: ids, title: "Close Tab",
                            symbol: "xmark.square", combo: keys("W", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.reload", appName: app, bundleIDs: ids, title: "Reload",
                            symbol: "arrow.clockwise", combo: keys("R", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.inPrivate", appName: app, bundleIDs: ids, title: "New InPrivate Window",
                            symbol: "eyeglasses", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.addressBar", appName: app, bundleIDs: ids, title: "Address Bar",
                            symbol: "link", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.favorite", appName: app, bundleIDs: ids, title: "Add to Favorites",
                            symbol: "star", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.favoritesBar", appName: app, bundleIDs: ids, title: "Show / Hide Favorites Bar",
                            symbol: "star.square", combo: keys("B", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.history", appName: app, bundleIDs: ids, title: "History",
                            symbol: "clock.arrow.circlepath", combo: keys("Y", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.downloads", appName: app, bundleIDs: ids, title: "Downloads",
                            symbol: "arrow.down.circle", combo: keys("L", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.readAloud", appName: app, bundleIDs: ids, title: "Read Aloud",
                            symbol: "speaker.wave.2", combo: keys("U", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "edge.find", appName: app, bundleIDs: ids, title: "Find on Page",
                            symbol: "magnifyingglass", combo: keys("F", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Spotify

    private static let spotify: [AppActionPreset] = {
        let app = "Spotify"
        let ids = ["com.spotify.client"]
        let doc = "https://support.spotify.com/us/article/keyboard-shortcuts/"
        return [
            AppActionPreset(id: "spotify.playPause", appName: app, bundleIDs: ids, title: "Play / Pause",
                            symbol: "playpause.fill", combo: keys("Space", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "spotify.like", appName: app, bundleIDs: ids, title: "Like / Unlike Song",
                            symbol: "heart", combo: keys("B", [.option, .shift]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "spotify.shuffle", appName: app, bundleIDs: ids, title: "Shuffle",
                            symbol: "shuffle", combo: keys("S", [.option]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "spotify.repeat", appName: app, bundleIDs: ids, title: "Repeat",
                            symbol: "repeat", combo: keys("R", [.option]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "spotify.mute", appName: app, bundleIDs: ids, title: "Mute / Unmute",
                            symbol: "speaker.slash", combo: keys("M", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "spotify.search", appName: app, bundleIDs: ids, title: "Search",
                            symbol: "magnifyingglass", combo: keys("K", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "spotify.nowPlaying", appName: app, bundleIDs: ids, title: "Now Playing",
                            symbol: "music.note", combo: keys("J", [.option, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "spotify.queue", appName: app, bundleIDs: ids, title: "Queue",
                            symbol: "list.bullet", combo: keys("Q", [.option, .shift]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "spotify.likedSongs", appName: app, bundleIDs: ids, title: "Liked Songs",
                            symbol: "heart.circle", combo: keys("S", [.option, .shift]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Apple Music

    private static let music: [AppActionPreset] = {
        let app = "Apple Music"
        let ids = ["com.apple.Music"]
        let doc = "https://support.apple.com/guide/music/keyboard-shortcuts-mus1019/mac"
        return [
            AppActionPreset(id: "music.playPause", appName: app, bundleIDs: ids, title: "Play / Pause",
                            symbol: "playpause.fill", combo: keys("Space", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "music.next", appName: app, bundleIDs: ids, title: "Next Song",
                            symbol: "forward.fill", combo: keys("→", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "music.previous", appName: app, bundleIDs: ids, title: "Previous Song",
                            symbol: "backward.fill", combo: keys("←", []),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "music.volumeUp", appName: app, bundleIDs: ids, title: "Volume Up",
                            symbol: "speaker.wave.3.fill", combo: keys("↑", [.command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "music.volumeDown", appName: app, bundleIDs: ids, title: "Volume Down",
                            symbol: "speaker.wave.1.fill", combo: keys("↓", [.command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "music.stop", appName: app, bundleIDs: ids, title: "Stop",
                            symbol: "stop.fill", combo: keys(".", [.command]),
                            delivery: .bringToFrontAndReturn, source: doc),
            AppActionPreset(id: "music.currentSong", appName: app, bundleIDs: ids, title: "Show Current Song",
                            symbol: "music.note", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "music.queue", appName: app, bundleIDs: ids, title: "Show Queue",
                            symbol: "list.bullet", combo: keys("U", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "music.miniPlayer", appName: app, bundleIDs: ids, title: "MiniPlayer",
                            symbol: "rectangle.inset.topright.filled", combo: keys("M", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "music.fullScreen", appName: app, bundleIDs: ids, title: "Full Screen Player",
                            symbol: "arrow.up.left.and.arrow.down.right", combo: keys("F", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "music.search", appName: app, bundleIDs: ids, title: "Search",
                            symbol: "magnifyingglass", combo: keys("F", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Finder

    private static let finder: [AppActionPreset] = {
        let app = "Finder"
        let ids = ["com.apple.finder"]
        let doc = "https://support.apple.com/en-us/102650"
        return [
            AppActionPreset(id: "finder.newWindow", appName: app, bundleIDs: ids, title: "New Finder Window",
                            symbol: "macwindow", combo: keys("N", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.newFolder", appName: app, bundleIDs: ids, title: "New Folder",
                            symbol: "folder.badge.plus", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.goToFolder", appName: app, bundleIDs: ids, title: "Go to Folder",
                            symbol: "folder", combo: keys("G", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.downloads", appName: app, bundleIDs: ids, title: "Downloads",
                            symbol: "arrow.down.circle", combo: keys("L", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.desktop", appName: app, bundleIDs: ids, title: "Desktop",
                            symbol: "desktopcomputer", combo: keys("D", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.home", appName: app, bundleIDs: ids, title: "Home",
                            symbol: "house", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.documents", appName: app, bundleIDs: ids, title: "Documents",
                            symbol: "doc", combo: keys("O", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.airdrop", appName: app, bundleIDs: ids, title: "AirDrop",
                            symbol: "airplayaudio", combo: keys("R", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.connect", appName: app, bundleIDs: ids, title: "Connect to Server",
                            symbol: "network", combo: keys("K", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.getInfo", appName: app, bundleIDs: ids, title: "Get Info",
                            symbol: "info.circle", combo: keys("I", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.quickLook", appName: app, bundleIDs: ids, title: "Quick Look",
                            symbol: "eye", combo: keys("Y", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "finder.trash", appName: app, bundleIDs: ids, title: "Move to Trash",
                            symbol: "trash", combo: keys("Delete", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Mail

    private static let mail: [AppActionPreset] = {
        let app = "Mail"
        let ids = ["com.apple.mail"]
        let doc = "https://support.apple.com/guide/mail/keyboard-shortcuts-mlhlb94f262b/mac"
        return [
            AppActionPreset(id: "mail.new", appName: app, bundleIDs: ids, title: "New Email",
                            symbol: "square.and.pencil", combo: keys("N", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.getMail", appName: app, bundleIDs: ids, title: "Get New Mail",
                            symbol: "tray.and.arrow.down", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.send", appName: app, bundleIDs: ids, title: "Send",
                            symbol: "paperplane", combo: keys("D", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.reply", appName: app, bundleIDs: ids, title: "Reply",
                            symbol: "arrowshape.turn.up.left", combo: keys("R", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.replyAll", appName: app, bundleIDs: ids, title: "Reply All",
                            symbol: "arrowshape.turn.up.left.2", combo: keys("R", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.forward", appName: app, bundleIDs: ids, title: "Forward",
                            symbol: "arrowshape.turn.up.right", combo: keys("F", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.archive", appName: app, bundleIDs: ids, title: "Archive",
                            symbol: "archivebox", combo: keys("A", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.markRead", appName: app, bundleIDs: ids, title: "Mark Read / Unread",
                            symbol: "envelope.open", combo: keys("U", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.junk", appName: app, bundleIDs: ids, title: "Move to Junk",
                            symbol: "xmark.bin", combo: keys("J", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.movePredicted", appName: app, bundleIDs: ids, title: "Move to Predicted Mailbox",
                            symbol: "folder", combo: keys("M", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.filter", appName: app, bundleIDs: ids, title: "Filter Mailbox",
                            symbol: "line.3.horizontal.decrease.circle", combo: keys("L", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "mail.sidebar", appName: app, bundleIDs: ids, title: "Show / Hide Sidebar",
                            symbol: "sidebar.left", combo: keys("S", [.control, .command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()

    // MARK: Notes

    private static let notes: [AppActionPreset] = {
        let app = "Notes"
        let ids = ["com.apple.Notes"]
        let doc = "https://support.apple.com/guide/notes/keyboard-shortcuts-and-gestures-apd46c25187e/mac"
        return [
            AppActionPreset(id: "notes.new", appName: app, bundleIDs: ids, title: "New Note",
                            symbol: "square.and.pencil", combo: keys("N", [.command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.newFolder", appName: app, bundleIDs: ids, title: "New Folder",
                            symbol: "folder.badge.plus", combo: keys("N", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.search", appName: app, bundleIDs: ids, title: "Search All Notes",
                            symbol: "magnifyingglass", combo: keys("F", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.checklist", appName: app, bundleIDs: ids, title: "Checklist",
                            symbol: "checklist", combo: keys("L", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.checkItem", appName: app, bundleIDs: ids, title: "Check / Uncheck Item",
                            symbol: "checkmark.square", combo: keys("U", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.table", appName: app, bundleIDs: ids, title: "Insert Table",
                            symbol: "tablecells", combo: keys("T", [.option, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.title", appName: app, bundleIDs: ids, title: "Title Format",
                            symbol: "textformat.size", combo: keys("T", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.heading", appName: app, bundleIDs: ids, title: "Heading Format",
                            symbol: "textformat", combo: keys("H", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.bullets", appName: app, bundleIDs: ids, title: "Bulleted List",
                            symbol: "list.bullet", combo: keys("7", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.attach", appName: app, bundleIDs: ids, title: "Attach File",
                            symbol: "paperclip", combo: keys("A", [.shift, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.sidebar", appName: app, bundleIDs: ids, title: "Show / Hide Sidebar",
                            symbol: "sidebar.left", combo: keys("S", [.control, .command]),
                            delivery: .bringToFront, source: doc),
            AppActionPreset(id: "notes.duplicate", appName: app, bundleIDs: ids, title: "Duplicate Note",
                            symbol: "plus.square.on.square", combo: keys("D", [.command]),
                            delivery: .bringToFront, source: doc),
        ]
    }()
}
