import Foundation
import Combine

/// Manages text snippets for a terminal panel.
/// Each snippet is a block of text separated by newlines. Double-clicking a snippet
/// sends it to the terminal. Persistence is handled via session restore.
@MainActor
final class SnippetEditorStore: ObservableObject {
    /// The raw text content of the editor
    @Published var text: String = ""

    /// Whether the snippet sidebar is visible
    @Published var isVisible: Bool = false

    /// The width of the snippet editor sidebar
    @Published var width: CGFloat = 280

    /// The terminal panel ID this store is associated with
    let terminalId: UUID

    static let minWidth: CGFloat = 180
    static let maxWidth: CGFloat = 600
    static let defaultWidth: CGFloat = 280

    init(terminalId: UUID) {
        self.terminalId = terminalId
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

}
