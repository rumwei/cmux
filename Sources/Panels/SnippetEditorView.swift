import SwiftUI
import AppKit

/// A sidebar text editor for terminal snippets.
/// Text is divided into blocks by empty lines. Double-clicking a block sends it to the terminal.
struct SnippetEditorView: View {
    @ObservedObject var store: SnippetEditorStore
    let onSendSnippet: (String) -> Void
    let onClose: () -> Void

    @State private var hoveredSnippetId: Int?
    @State private var shouldFocusEditor: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editorContent
        }
        .frame(width: 280)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            shouldFocusEditor = true
        }
    }

    private var header: some View {
        HStack {
            Text(String(localized: "snippetEditor.title", defaultValue: "Snippets"))
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "snippetEditor.close", defaultValue: "Close Snippets (⌘E)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var editorContent: some View {
        if store.snippets.isEmpty && store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyState
        } else {
            snippetList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(String(localized: "snippetEditor.emptyTitle", defaultValue: "No Snippets"))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(String(localized: "snippetEditor.emptyDescription", defaultValue: "Type commands here.\nSeparate snippets with blank lines.\nDouble-click to send to terminal."))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            textEditor
                .frame(maxHeight: 200)
        }
        .padding()
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.snippets) { snippet in
                        SnippetBlockView(
                            snippet: snippet,
                            isHovered: hoveredSnippetId == snippet.id,
                            onDoubleTap: {
                                onSendSnippet(snippet.content)
                            }
                        )
                        .onHover { isHovered in
                            hoveredSnippetId = isHovered ? snippet.id : nil
                        }
                    }
                }
                .padding(8)
            }

            Divider()

            textEditor
                .frame(height: 120)
        }
    }

    private var textEditor: some View {
        SnippetTextEditor(text: $store.text, shouldFocus: shouldFocusEditor)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocusEditor = false
                }
            }
    }
}

/// A single snippet block that can be double-clicked to send
struct SnippetBlockView: View {
    let snippet: SnippetEditorStore.Snippet
    let isHovered: Bool
    let onDoubleTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snippet.content)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if snippet.lineCount > 1 {
                Text("\(snippet.lineCount) lines")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .help(String(localized: "snippetEditor.doubleClickHint", defaultValue: "Double-click to send to terminal"))
    }
}

/// NSTextView wrapper for the snippet editor
struct SnippetTextEditor: NSViewRepresentable {
    @Binding var text: String
    var shouldFocus: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SnippetNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        if shouldFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SnippetTextEditor

        init(_ parent: SnippetTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// Custom NSTextView that accepts first responder and properly handles keyboard input
class SnippetNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self {
            return super.performKeyEquivalent(with: event)
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            NotificationCenter.default.post(name: .snippetEditorDidBecomeFirstResponder, object: self)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            NotificationCenter.default.post(name: .snippetEditorDidResignFirstResponder, object: self)
        }
        return result
    }
}

extension Notification.Name {
    static let snippetEditorDidBecomeFirstResponder = Notification.Name("snippetEditorDidBecomeFirstResponder")
    static let snippetEditorDidResignFirstResponder = Notification.Name("snippetEditorDidResignFirstResponder")
}

#if DEBUG
struct SnippetEditorView_Previews: PreviewProvider {
    static var previews: some View {
        SnippetEditorView(
            store: {
                let store = SnippetEditorStore(terminalId: UUID())
                store.text = """
                ls -la

                cd /tmp
                pwd

                echo "Hello World"
                """
                return store
            }(),
            onSendSnippet: { _ in },
            onClose: {}
        )
    }
}
#endif
