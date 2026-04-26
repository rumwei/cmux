import Foundation
import Combine

/// Manages text snippets for a terminal panel, persisted to disk.
/// Each snippet is a block of text separated by newlines. Double-clicking a snippet
/// sends it to the terminal.
@MainActor
final class SnippetEditorStore: ObservableObject {
    /// The raw text content of the editor
    @Published var text: String = "" {
        didSet {
            scheduleSave()
        }
    }

    /// Whether the snippet sidebar is visible
    @Published var isVisible: Bool = false

    /// The terminal panel ID this store is associated with
    let terminalId: UUID

    private var saveWorkItem: DispatchWorkItem?
    private static let saveDebounceInterval: TimeInterval = 0.5

    init(terminalId: UUID) {
        self.terminalId = terminalId
        loadFromDisk()
    }

    // MARK: - Snippet Parsing

    /// Parses the text into individual snippet blocks separated by empty lines.
    /// Each block is a contiguous group of non-empty lines.
    var snippets: [Snippet] {
        var result: [Snippet] = []
        var currentLines: [String] = []
        var startLine = 0

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !currentLines.isEmpty {
                    result.append(Snippet(
                        id: startLine,
                        content: currentLines.joined(separator: "\n"),
                        lineRange: startLine..<index
                    ))
                    currentLines = []
                }
            } else {
                if currentLines.isEmpty {
                    startLine = index
                }
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            result.append(Snippet(
                id: startLine,
                content: currentLines.joined(separator: "\n"),
                lineRange: startLine..<lines.count
            ))
        }

        return result
    }

    struct Snippet: Identifiable, Equatable {
        let id: Int
        let content: String
        let lineRange: Range<Int>

        var preview: String {
            let firstLine = content.components(separatedBy: "\n").first ?? content
            if firstLine.count > 50 {
                return String(firstLine.prefix(47)) + "..."
            }
            return firstLine
        }

        var lineCount: Int {
            content.components(separatedBy: "\n").count
        }
    }

    // MARK: - Persistence

    private static var snippetsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cmuxDir = appSupport.appendingPathComponent("cmux", isDirectory: true)
        return cmuxDir.appendingPathComponent("snippets", isDirectory: true)
    }

    private var fileURL: URL {
        Self.snippetsDirectory.appendingPathComponent("\(terminalId.uuidString).txt")
    }

    private func loadFromDisk() {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            text = content
        } catch {
            text = ""
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveToDisk()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.saveDebounceInterval,
            execute: workItem
        )
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(
                at: Self.snippetsDirectory,
                withIntermediateDirectories: true
            )
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save snippets: \(error)")
        }
    }

    func deleteFromDisk() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Static Methods

    /// Migrate snippet file when terminal ID changes (e.g., session restore)
    static func migrateSnippets(from oldId: UUID, to newId: UUID) {
        let oldURL = snippetsDirectory.appendingPathComponent("\(oldId.uuidString).txt")
        let newURL = snippetsDirectory.appendingPathComponent("\(newId.uuidString).txt")

        guard FileManager.default.fileExists(atPath: oldURL.path) else { return }
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return }

        try? FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    /// Clean up orphaned snippet files for terminals that no longer exist
    static func cleanupOrphanedSnippets(activeTerminalIds: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: snippetsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "txt" {
            let filename = file.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: filename), !activeTerminalIds.contains(uuid) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
