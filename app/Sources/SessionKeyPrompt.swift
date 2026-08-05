import AppKit

enum SessionKeyPrompt {
    /// Modal sheet-less prompt for the claude.ai session key. Returns nil if cancelled.
    static func show(existing: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = existing ? "Update session key" : "Set session key"
        alert.informativeText = "Paste your claude.ai sessionKey cookie value (starts with sk-ant-sid…)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-sid…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
