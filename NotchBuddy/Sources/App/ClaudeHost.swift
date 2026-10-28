import AppKit

// MARK: - ClaudeHost
//
// The app a Claude Code session runs in, from the hook payload's term_program /
// bundle_id. VS Code sessions keep the original "VS Code" pill; sessions from a
// terminal also route to integration_claude and the pill says "Claude Code".

struct ClaudeHost: Equatable {
    let bundleId: String
    let name: String

    /// UserDefaults key: show terminal sessions' questions and permission requests in the
    /// notch (they then wait for the notch). Off by default: the terminal asks itself.
    static let terminalCardsKey = "terminalCardsEnabled"
    static var terminalCardsEnabled: Bool { UserDefaults.standard.bool(forKey: terminalCardsKey) }

    /// Terminals (and agent apps like Conductor) accepted for Claude Code sessions.
    /// Keyed by bundle id; the second
    /// table maps TERM_PROGRAM for hooks that run without __CFBundleIdentifier.
    private static let terminals: [String: String] = [
        "dev.warp.Warp-Stable":       "Warp",
        "dev.warp.Warp-Preview":      "Warp",
        "com.apple.Terminal":         "Terminal",
        "com.googlecode.iterm2":      "iTerm",
        "com.mitchellh.ghostty":      "Ghostty",
        "net.kovidgoyal.kitty":       "kitty",
        "org.alacritty":              "Alacritty",
        "com.github.wez.wezterm":     "WezTerm",
        "co.zeit.hyper":              "Hyper",
        "dev.zed.Zed":                "Zed",
        "com.cmuxterm.app":           "cmux",    // sets TERM_PROGRAM=ghostty: the bundle id decides
        "com.stablyai.orca":          "Orca",
        "com.conductor.app":          "Conductor", // runs Claude Code with no TERM_PROGRAM
        "com.laminef.claudex":        "Claudex", // runs Claude Code in tmux (TERM_PROGRAM=tmux): the bundle id decides
    ]
    private static let termPrograms: [String: String] = [
        "warpterminal":   "dev.warp.Warp-Stable",
        "apple_terminal": "com.apple.Terminal",
        "iterm.app":      "com.googlecode.iterm2",
        "ghostty":        "com.mitchellh.ghostty",
        "kitty":          "net.kovidgoyal.kitty",
        "alacritty":      "org.alacritty",
        "wezterm":        "com.github.wez.wezterm",
        "hyper":          "co.zeit.hyper",
        "zed":            "dev.zed.Zed",
    ]

    /// The terminal a session runs in, or nil when it isn't a known terminal.
    static func terminal(termProgram: String, bundleId: String) -> ClaudeHost? {
        if let name = terminals[bundleId] { return ClaudeHost(bundleId: bundleId, name: name) }
        if let id = termPrograms[termProgram.lowercased()], let name = terminals[id] {
            return ClaudeHost(bundleId: id, name: name)
        }
        return nil
    }

    /// The app name for a task's host; nil host means VS Code (the original routing).
    static func name(for hostBundleId: String?) -> String {
        guard let id = hostBundleId, let name = terminals[id] else { return "VS Code" }
        return name
    }

    /// Pill label for integration_claude: "VS Code" for editor sessions, "Claude Code" otherwise.
    static func pillName(hostApp: String?) -> String {
        hostApp == nil ? "VS Code" : "Claude Code"
    }

    /// Hosts that open one session from a link, keyed by bundle id: "Open" goes to the
    /// session's own tab instead of only bringing the app forward.
    private static let sessionLinks: [String: String] = [
        "com.laminef.claudex": "claudex://session/", // the tab of that Claude Code session
    ]

    /// Hosts with tabs that say which session is on screen, keyed by bundle id: a file,
    /// relative to the home folder, holding the visible session's id (or an empty line).
    private static let visibleSessionFiles: [String: String] = [
        "com.laminef.claudex": ".claude/claudex/session-visible",
    ]

    /// Is the session already in front of the user? Its host is the frontmost app and,
    /// for a host that says which tab is on screen, that tab is this session. A host
    /// that says nothing (or an older version without the file) counts as showing it.
    static func sessionInFront(hostApp: String?, frontmost: String?, sessionId: String,
                               readVisible: (String) -> String? = ClaudeHost.readVisibleSession) -> Bool {
        guard let host = hostApp, host == frontmost else { return false }
        guard let file = visibleSessionFiles[host], let visible = readVisible(file) else { return true }
        return visible.trimmingCharacters(in: .whitespacesAndNewlines) == sessionId
    }

    /// Reads a visible-session file under the home folder; nil when it does not exist.
    static func readVisibleSession(_ relativePath: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The link that opens this session in its host, or nil when the host has none
    /// or the session id is not a plain id (letters, digits and hyphens).
    static func sessionURL(hostBundleId: String?, sessionId: String?) -> URL? {
        guard let host = hostBundleId, let prefix = sessionLinks[host],
              let id = sessionId, !id.isEmpty, id.count <= 64,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return URL(string: prefix + id)
    }

    /// Brings the session's terminal forward (launching it if needed), on the session
    /// itself when the host can open it from a link. false when not a terminal host.
    @discardableResult
    static func activate(_ hostBundleId: String?, sessionId: String? = nil) -> Bool {
        guard let id = hostBundleId, terminals[id] != nil else { return false }
        if let url = sessionURL(hostBundleId: id, sessionId: sessionId),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
            return true
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
        return true
    }
}
