import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection
            
            Divider()
            
            // Status Section
            statusSection
            
            // Permissions Section (if needed)
            if !appState.permissionsService.allPermissionsGranted {
                Divider()
                permissionsSection
            }
            
            Divider()
            
            // Note Mode
            noteModeSection
            Divider()

            // Last Transcription
            if !appState.lastTranscription.isEmpty {
                lastTranscriptionSection
                Divider()
            }

            // Shortcut Info
            shortcutSection
            
            Divider()
            
            // Actions
            actionsSection
        }
        .padding()
        .frame(width: 320)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            Text("🎙️")
                .font(.title2)
            
            Text("LocalWhisper")
                .font(.headline)
            
            Spacer()
            
            statusBadge
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(appState.transcriptionState.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch appState.transcriptionState {
        case .idle:
            return appState.isModelLoaded ? .green : .yellow
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .error:
            return .orange
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model Status
            HStack {
                Image(systemName: appState.isModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundColor(appState.isModelLoaded ? .green : .orange)
                
                if appState.isModelLoaded {
                    Text("Model loaded: \(appState.selectedModel)")
                        .font(.caption)
                } else if appState.modelLoadProgress > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loading model...")
                            .font(.caption)
                        ProgressView(value: appState.modelLoadProgress)
                            .progressViewStyle(.linear)
                    }
                } else {
                    Text("Model not loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Error Message
            if let error = appState.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    // MARK: - Permissions Section
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions Required")
                .font(.caption)
                .fontWeight(.semibold)
            
            // Microphone
            MenuPermissionRow(
                icon: "mic.fill",
                title: "Microphone",
                granted: appState.permissionsService.microphoneGranted,
                action: { appState.permissionsService.openMicrophoneSettings() }
            )
            
            // Accessibility
            MenuPermissionRow(
                icon: "accessibility",
                title: "Accessibility",
                granted: appState.permissionsService.accessibilityGranted,
                action: { appState.permissionsService.requestAccessibilityPermission() }
            )
        }
    }
    
    // MARK: - Last Transcription
    @State private var showCopiedFeedback = false
    
    @State private var showReinjectedFeedback = false

    private var lastTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last Transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if showCopiedFeedback {
                    Text("Copied!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                } else if showReinjectedFeedback {
                    Text("Re-injected!")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .transition(.opacity)
                }
            }

            Button(action: copyTranscriptionToClipboard) {
                Text(appState.lastTranscription)
                    .font(.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Click to copy to clipboard")

            HStack(spacing: 8) {
                Button {
                    copyTranscriptionToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    reinjectLastTranscription()
                } label: {
                    Label("Re-inject", systemImage: "arrow.uturn.right.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Type this text into the focused app again")

                Spacer()
            }
        }
    }

    private func copyTranscriptionToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.lastTranscription, forType: .string)

        withAnimation {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    private func reinjectLastTranscription() {
        let text = appState.lastTranscription
        guard !text.isEmpty else { return }
        let useClipboard = appState.useClipboardFallback
        let simulate = appState.useSimulateKeypresses
        Task {
            do {
                try await appState.textInjectionService.injectText(
                    text,
                    useClipboardFallback: useClipboard,
                    useSimulateKeypresses: simulate
                )
                await MainActor.run {
                    withAnimation { showReinjectedFeedback = true }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation { showReinjectedFeedback = false }
                }
            } catch {
                print("[MenuBar] Re-inject failed: \(error)")
            }
        }
    }
    
    // MARK: - Note Mode

    private var noteModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI Notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if appState.noteState != .idle {
                    Text(appState.noteState.description)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                switch appState.noteState {
                case .idle, .error:
                    Button {
                        Task { await appState.coordinator.startNoteRecording() }
                    } label: {
                        Label("Start Note", systemImage: "record.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                case .recording:
                    Button {
                        Task { await appState.coordinator.stopNoteRecording() }
                    } label: {
                        Label("Stop · \(formatElapsed(appState.noteElapsedSeconds))", systemImage: "stop.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                case .transcribing, .summarizing:
                    ProgressView().scaleEffect(0.6)
                    Text(appState.noteState.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Shortcut Section
    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keyboard Shortcut")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text(HotkeyManager.shared.shortcutString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                Text("Hold to record")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        HStack {
            Button("Settings...") {
                // Post notification to open settings
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Menu Permission Row (simplified version for menu)
struct MenuPermissionRow: View {
    let icon: String
    let title: String
    let granted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
            
            Spacer()
            
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
