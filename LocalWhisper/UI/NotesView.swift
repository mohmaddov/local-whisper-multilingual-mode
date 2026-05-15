import SwiftUI
import UniformTypeIdentifiers

struct NotesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var notes: [Note] = []
    @State private var selection: Note.ID?
    @State private var search: String = ""
    @State private var loaded = false
    @State private var editingTitle: Bool = false
    @State private var draftTitle: String = ""

    private var filtered: [Note] {
        guard !search.isEmpty else { return notes }
        let q = search.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(q)
            || $0.markdown.lowercased().contains(q)
            || $0.rawTranscription.lowercased().contains(q)
        }
    }

    private var sections: [NoteDateSection] {
        NoteDateSection.group(filtered)
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detail
                .frame(minWidth: 420)
        }
        .task {
            if !loaded { await refresh() }
        }
        .onChange(of: appState.noteState) { _, newValue in
            if newValue == .idle {
                Task { await refresh() }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Toolbar: record button + search
            VStack(spacing: 10) {
                recordButton
                searchField
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // List of notes grouped by date
            if !loaded {
                Spacer()
                ProgressView()
                Spacer()
            } else if filtered.isEmpty {
                emptySidebarPlaceholder
            } else {
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.notes) { note in
                                NoteRow(note: note, isSelected: selection == note.id)
                                    .tag(note.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()

            // Footer: open folder
            HStack {
                Button {
                    NSWorkspace.shared.open(NoteService.folderURL)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open notes folder")

                Spacer()

                Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.background)
    }

    @ViewBuilder
    private var recordButton: some View {
        switch appState.noteState {
        case .idle, .error:
            Button {
                Task { await appState.coordinator.startNoteRecording() }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 9, height: 9)
                    Text("New Recording")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

        case .recording:
            Button {
                Task { await appState.coordinator.stopNoteRecording() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text("Stop · \(formatElapsed(appState.noteElapsedSeconds))")
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)

        case .transcribing, .summarizing:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text(appState.noteState.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptySidebarPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "note.text")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text(notes.isEmpty ? "No notes yet" : "No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let note = notes.first(where: { $0.id == id }) {
            NoteDetailView(note: note, onDelete: {
                Task {
                    await appState.noteService.delete(id: note.id)
                    await refresh()
                    selection = nil
                }
            }, onRename: { newTitle in
                var updated = note
                updated.title = newTitle
                Task {
                    await appState.noteService.update(updated)
                    await refresh()
                }
            })
            .id(note.id)
        } else if notes.isEmpty {
            EmptyNotesPlaceholder()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Select a note")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
    }

    private func refresh() async {
        notes = await appState.noteService.readAll()
        loaded = true
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Date grouping

struct NoteDateSection: Identifiable {
    let id: String
    let title: String
    let notes: [Note]

    static func group(_ notes: [Note]) -> [NoteDateSection] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
              let weekAgo = cal.date(byAdding: .day, value: -7, to: today),
              let monthAgo = cal.date(byAdding: .day, value: -30, to: today)
        else { return [NoteDateSection(id: "all", title: "All", notes: notes)] }

        var todayNotes: [Note] = []
        var yesterdayNotes: [Note] = []
        var weekNotes: [Note] = []
        var monthNotes: [Note] = []
        var olderNotes: [Note] = []
        for n in notes {
            if n.timestamp >= today {
                todayNotes.append(n)
            } else if n.timestamp >= yesterday {
                yesterdayNotes.append(n)
            } else if n.timestamp >= weekAgo {
                weekNotes.append(n)
            } else if n.timestamp >= monthAgo {
                monthNotes.append(n)
            } else {
                olderNotes.append(n)
            }
        }
        var sections: [NoteDateSection] = []
        if !todayNotes.isEmpty { sections.append(.init(id: "today", title: "Today", notes: todayNotes)) }
        if !yesterdayNotes.isEmpty { sections.append(.init(id: "yesterday", title: "Yesterday", notes: yesterdayNotes)) }
        if !weekNotes.isEmpty { sections.append(.init(id: "week", title: "Previous 7 Days", notes: weekNotes)) }
        if !monthNotes.isEmpty { sections.append(.init(id: "month", title: "Previous 30 Days", notes: monthNotes)) }
        if !olderNotes.isEmpty { sections.append(.init(id: "older", title: "Earlier", notes: olderNotes)) }
        return sections
    }
}

// MARK: - Sidebar row

struct NoteRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !note.detectedLanguages.isEmpty {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(note.detectedLanguages.map { TranscriptionRecord.languageFlag($0) }.joined())
                        .font(.caption2)
                }
                if !note.llmSucceeded {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("No AI summary")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var timeLabel: String {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        let cal = Calendar.current
        if cal.isDateInToday(note.timestamp) || cal.isDateInYesterday(note.timestamp) {
            return df.string(from: note.timestamp)
        }
        df.dateStyle = .short
        return df.string(from: note.timestamp)
    }

    private var snippet: String {
        let body = note.markdown
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if body.isEmpty { return note.rawTranscription }
        return body
    }

    private var durationLabel: String {
        let total = Int(note.durationSeconds)
        let m = total / 60
        let s = total % 60
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

// MARK: - Empty placeholder

struct EmptyNotesPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("AI Notes")
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)

            Text("Record meetings, interviews, or thoughts.\nThe local LLM transforms your audio into a clean, structured note.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            Text("Click **New Recording** in the sidebar to begin.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

// MARK: - Note Detail

struct NoteDetailView: View {
    let note: Note
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var showRaw = false
    @State private var showCopied = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Spacer()

                viewToggle

                Divider().frame(height: 16)

                Button {
                    copy()
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help(showCopied ? "Copied" : "Copy")

                Button {
                    exportMarkdown()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Export markdown")

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleHeader
                    metadataLine
                    Divider()

                    if showRaw {
                        Text(note.rawTranscription)
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownRendered(text: note.markdown)
                    }

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(.background)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var viewToggle: some View {
        Picker("", selection: $showRaw) {
            Text("Summary").tag(false)
            Text("Transcript").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    @ViewBuilder
    private var titleHeader: some View {
        if editingTitle {
            HStack {
                TextField("Title", text: $titleDraft, onCommit: commitTitle)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .textFieldStyle(.plain)
                Button("Save", action: commitTitle).keyboardShortcut(.return, modifiers: [])
                Button("Cancel") { editingTitle = false }
            }
        } else {
            HStack {
                Text(note.title)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    titleDraft = note.title
                    editingTitle = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rename")
            }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 12) {
            Label(formattedDate, systemImage: "calendar")
            Label(formattedDuration, systemImage: "clock")
            if !note.detectedLanguages.isEmpty {
                Text(note.detectedLanguages.map { TranscriptionRecord.languageFlag($0) }.joined())
            }
            if let llm = note.llmModel {
                Label(shortLLM(llm), systemImage: "brain")
            }
            if !note.llmSucceeded {
                Label("No AI summary", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func commitTitle() {
        let cleaned = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, cleaned != note.title {
            onRename(cleaned)
        }
        editingTitle = false
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(showRaw ? note.rawTranscription : note.markdown, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopied = false }
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

    private func shortLLM(_ id: String) -> String {
        String(id.split(separator: "/").last ?? Substring(id))
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

/// Lightweight markdown renderer with Apple-style typography.
struct MarkdownRendered: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks, id: \.self) { block in
                switch block.kind {
                case .h1:
                    Text(block.text)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .padding(.top, 10)
                case .h2:
                    Text(block.text)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .padding(.top, 8)
                case .h3:
                    Text(block.text)
                        .font(.headline)
                        .padding(.top, 4)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.tertiary)
                        inlineMarkdown(block.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .quote:
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        inlineMarkdown(block.text)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                case .paragraph:
                    inlineMarkdown(block.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(3)
                case .blank:
                    Color.clear.frame(height: 2)
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
