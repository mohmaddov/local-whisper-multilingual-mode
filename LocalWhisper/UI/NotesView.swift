import SwiftUI
import UniformTypeIdentifiers

struct NotesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var notes: [Note] = []
    @State private var selection: Note.ID?
    @State private var search: String = ""
    @State private var loaded = false

    private var filtered: [Note] {
        guard !search.isEmpty else { return notes }
        let q = search.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(q)
            || $0.markdown.lowercased().contains(q)
            || $0.rawTranscription.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detail
                .frame(minWidth: 400)
        }
        .task {
            if !loaded { await refresh() }
        }
        .onChange(of: appState.noteState) { _, newValue in
            // Auto-refresh once a note finishes processing.
            if newValue == .idle {
                Task { await refresh() }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding([.horizontal, .top], 12)

            if !loaded {
                Spacer()
                ProgressView()
                Spacer()
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(notes.isEmpty ? "No notes yet" : "No matches")
                        .foregroundStyle(.secondary)
                    if notes.isEmpty {
                        Text("Use the menu bar to start a note recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, selection: $selection) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button {
                    NSWorkspace.shared.open(NoteService.folderURL)
                } label: {
                    Image(systemName: "folder")
                }
                Spacer()
                if appState.noteState.isBusy {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text(appState.noteState.description).font(.caption2)
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let note = notes.first(where: { $0.id == id }) {
            NoteDetailView(note: note, onDelete: {
                Task {
                    await appState.noteService.delete(id: note.id)
                    await refresh()
                    selection = nil
                }
            })
        } else if notes.isEmpty {
            EmptyNotesPlaceholder()
        } else {
            VStack {
                Image(systemName: "note.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select a note")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func refresh() async {
        notes = await appState.noteService.readAll()
        loaded = true
    }
}

struct EmptyNotesPlaceholder: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.tint)

            Text("AI Notes")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                Text("Record long-form audio (meetings, interviews, ideas) and let the local LLM build a structured note for you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)

                Text("Open the menu bar icon and press **Start Note**.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if !note.llmSucceeded {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("AI summary unavailable — raw transcription only")
                }
            }
            HStack(spacing: 6) {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !note.detectedLanguages.isEmpty {
                    Text("·").foregroundStyle(.secondary)
                    Text(note.detectedLanguages.map { TranscriptionRecord.languageFlag($0) }.joined())
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: note.timestamp)
    }

    private var formattedDuration: String {
        let total = Int(note.durationSeconds)
        let m = total / 60
        let s = total % 60
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

struct NoteDetailView: View {
    let note: Note
    let onDelete: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var showRaw = false
    @State private var showCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Label(formattedDate, systemImage: "calendar")
                        Label(formattedDuration, systemImage: "clock")
                        if !note.detectedLanguages.isEmpty {
                            Text(note.detectedLanguages.map { TranscriptionRecord.languageFlag($0) }.joined())
                        }
                        if let llm = note.llmModel {
                            Label(llm.split(separator: "/").last.map(String.init) ?? llm, systemImage: "brain")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Actions
                HStack(spacing: 8) {
                    Button {
                        copyToClipboard(showRaw ? note.rawTranscription : note.markdown)
                    } label: {
                        Label(showCopied ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportMarkdown()
                    } label: {
                        Label("Export .md", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Toggle(isOn: $showRaw) {
                        Text("Raw transcription")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // Content
                if showRaw {
                    Text(note.rawTranscription)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Render markdown via SwiftUI's built-in support (macOS 12+).
                    MarkdownRendered(text: note.markdown)
                }

                Spacer(minLength: 40)
            }
            .padding(24)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        let isoDate = ISO8601DateFormatter().string(from: note.timestamp)
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(slug(note.title))-\(isoDate).md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? note.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func slug(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(40)
            .description
    }

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: note.timestamp)
    }

    private var formattedDuration: String {
        let total = Int(note.durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

/// Render a markdown string with headings, bullets, and emphasis using
/// SwiftUI's AttributedString markdown support.
struct MarkdownRendered: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks, id: \.self) { block in
                switch block.kind {
                case .h1:
                    Text(block.text).font(.title2).fontWeight(.bold).padding(.top, 6)
                case .h2:
                    Text(block.text).font(.title3).fontWeight(.semibold).padding(.top, 4)
                case .h3:
                    Text(block.text).font(.headline).padding(.top, 2)
                case .bullet:
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.tint)
                        inlineMarkdown(block.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .quote:
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 3)
                        inlineMarkdown(block.text)
                            .foregroundStyle(.secondary)
                    }
                case .paragraph:
                    inlineMarkdown(block.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .blank:
                    Color.clear.frame(height: 4)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inlineMarkdown(_ s: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnly)
        ) {
            return Text(attributed)
        }
        return Text(s)
    }

    private struct Block: Hashable {
        enum Kind { case h1, h2, h3, bullet, quote, paragraph, blank }
        let kind: Kind
        let text: String
    }

    private var blocks: [Block] {
        var out: [Block] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                out.append(Block(kind: .blank, text: ""))
            } else if trimmed.hasPrefix("# ") {
                out.append(Block(kind: .h1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                out.append(Block(kind: .h2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                out.append(Block(kind: .h3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                out.append(Block(kind: .bullet, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("> ") {
                out.append(Block(kind: .quote, text: String(trimmed.dropFirst(2))))
            } else {
                out.append(Block(kind: .paragraph, text: trimmed))
            }
        }
        return out
    }
}
