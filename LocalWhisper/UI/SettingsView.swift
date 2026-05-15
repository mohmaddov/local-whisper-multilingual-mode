import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Model", systemImage: "cpu")
                    .tag(0)
                Label("Vocabulary", systemImage: "text.book.closed")
                    .tag(1)
                Label("Shortcuts", systemImage: "keyboard")
                    .tag(2)
                Label("Permissions", systemImage: "lock.shield")
                    .tag(3)
                Label("Logs", systemImage: "doc.text.magnifyingglass")
                    .tag(4)
                Label("About", systemImage: "info.circle")
                    .tag(5)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
        } detail: {
            Group {
                switch selectedTab {
                case 0:
                    ModelSettingsView()
                case 1:
                    VocabularySettingsView()
                case 2:
                    ShortcutSettingsView()
                case 3:
                    PermissionsSettingsView()
                case 4:
                    LogsSettingsView()
                case 5:
                    AboutView()
                default:
                    ModelSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, minHeight: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(appState)
    }
}

// MARK: - Model Settings
struct ModelSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isReloading = false
    @State private var selectedModelIndex = 0
    
    private let models: [(id: String, name: String, size: String, description: String, repo: String?)] = [
        ("openai_whisper-medium", "Whisper Medium", "~1.5GB", "High accuracy, balanced performance", nil),
        ("distil-whisper_distil-large-v3_turbo", "Distil Large v3 Turbo", "~600MB", "Near large-v3 accuracy, much faster", nil),
        ("openai_whisper-large-v3-v20240930_turbo", "Whisper Large v3 Turbo", "~1.6GB", "Fast & accurate, latest checkpoint", nil),
        ("openai_whisper-large-v3-v20240930", "Whisper Large v3", "~3GB", "Best Whisper accuracy, latest checkpoint", nil),
        ("nvidia_parakeet-v3_494MB", "Parakeet v3", "~494MB", "NVIDIA Parakeet v3, compact & accurate", "argmaxinc/parakeetkit-pro"),
        ("nvidia_parakeet-v3", "Parakeet v3 Full", "~1.3GB", "NVIDIA Parakeet v3, highest accuracy", "argmaxinc/parakeetkit-pro")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Whisper Model")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Choose a model based on your needs. Larger models are more accurate but slower.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Current Status
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(appState.isModelLoaded ? Color.green.opacity(0.2) : Color.yellow.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: appState.isModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(appState.isModelLoaded ? .green : .yellow)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.isModelLoaded ? "Model Ready" : "Loading Model...")
                            .font(.headline)
                        Text(appState.selectedModel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if !appState.isModelLoaded && appState.modelLoadProgress > 0 {
                        ProgressView(value: appState.modelLoadProgress)
                            .frame(width: 100)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Model Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Model")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(models, id: \.id) { model in
                            ModelCard(
                                model: model,
                                isSelected: appState.selectedModel == model.id,
                                isLoading: isReloading && appState.selectedModel == model.id
                            ) {
                                selectModel(model.id, repo: model.repo)
                            }
                        }
                    }
                }
                
                // Multilingual Mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("Language")
                        .font(.headline)

                    Toggle(isOn: $appState.multilingualMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Multilingual mode")
                            Text("Detects the language every 5 seconds — switch between English, French, Russian or any language mid-sentence.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    if !appState.multilingualMode {
                        Picker("", selection: $appState.language) {
                            Text("Auto-detect").tag("")
                            Divider()
                            Text("English").tag("en")
                            Text("French").tag("fr")
                            Text("Russian").tag("ru")
                            Text("Chinese").tag("zh")
                            Text("Spanish").tag("es")
                            Text("German").tag("de")
                            Text("Japanese").tag("ja")
                            Text("Korean").tag("ko")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                }
                
                // Recording Options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recording Options")
                        .font(.headline)
                    
                    Toggle(isOn: $appState.muteAudioWhileRecording) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mute speakers while recording")
                            Text("Prevents the microphone from picking up audio playing from your speakers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Text Injection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text Injection")
                        .font(.headline)
                    
                    Toggle(isOn: $appState.useSimulateKeypresses) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulate keypresses")
                            Text("Types each character individually instead of pasting. Useful for apps that don't support Cmd+V (e.g., Emacs, terminals).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
    
    private func selectModel(_ modelId: String, repo: String? = nil) {
        guard modelId != appState.selectedModel || !appState.isModelLoaded else { return }
        
        appState.selectedModel = modelId
        isReloading = true
        
        Task {
            await appState.transcriptionService.unloadModel()
            await MainActor.run {
                appState.isModelLoaded = false
            }
            await appState.transcriptionService.loadModel(modelName: modelId, modelRepo: repo)
            let loaded = await appState.transcriptionService.isModelLoaded
            await MainActor.run {
                appState.isModelLoaded = loaded
                isReloading = false
            }
        }
    }
}

// MARK: - Model Card
struct ModelCard: View {
    let model: (id: String, name: String, size: String, description: String, repo: String?)
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.name)
                        .font(.headline)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                
                Text(model.size)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vocabulary Settings
struct VocabularySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newWord = ""
    @State private var editingIndex: Int?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Vocabulary")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Add words or phrases to improve transcription accuracy for names, technical terms, or domain-specific vocabulary.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Add new word
                HStack(spacing: 12) {
                    TextField("Add a word or phrase...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWord()
                        }
                    
                    Button(action: addWord) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                // Word list
                if appState.customVocabulary.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No custom words yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Add words that you frequently use or that are often misheard.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.customVocabulary.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(word)
                                    .font(.body)
                                
                                Spacer()
                                
                                Button {
                                    removeWord(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            if index < appState.customVocabulary.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Tips
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tips", systemImage: "lightbulb")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        tipRow("Add proper nouns, names, and brand names")
                        tipRow("Include technical terms or jargon")
                        tipRow("Add words that are often misheard or misspelled")
                        tipRow("Use correct capitalization for names")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(24)
        }
    }
    
    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
    
    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !appState.customVocabulary.contains(trimmed) else {
            newWord = ""
            return
        }
        
        withAnimation {
            appState.customVocabulary.append(trimmed)
        }
        newWord = ""
    }
    
    private func removeWord(at index: Int) {
        _ = withAnimation {
            appState.customVocabulary.remove(at: index)
        }
    }
}

// MARK: - Shortcut Settings
struct ShortcutSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecording = false
    @State private var currentShortcut = HotkeyManager.shared.shortcutString
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure how you trigger voice transcription.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Current shortcut
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recording Shortcut")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        // Shortcut display / recorder
                        ShortcutRecorderView(
                            isRecording: $isRecording,
                            currentShortcut: $currentShortcut
                        )
                        
                        Spacer()
                        
                        if !isRecording {
                            Button("Change") {
                                isRecording = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    
                    Text("Hold to record, release to transcribe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Preset shortcuts
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Presets")
                        .font(.headline)
                    
                    // First row - Primary options
                    HStack(spacing: 12) {
                        PresetShortcutButton(
                            label: "🌐 Globe Key",
                            keyCode: 63,  // Globe/Fn key
                            modifiers: [],
                            currentShortcut: $currentShortcut,
                            isRecommended: true
                        )
                        
                        PresetShortcutButton(
                            label: "⌃⇧Space",
                            keyCode: UInt16(kVK_Space),
                            modifiers: [.maskControl, .maskShift],
                            currentShortcut: $currentShortcut
                        )
                    }
                    
                    // Second row
                    HStack(spacing: 12) {
                        PresetShortcutButton(
                            label: "⌥Space",
                            keyCode: UInt16(kVK_Space),
                            modifiers: [.maskAlternate],
                            currentShortcut: $currentShortcut
                        )
                        
                        PresetShortcutButton(
                            label: "Fn+F5",
                            keyCode: UInt16(kVK_F5),
                            modifiers: [],
                            currentShortcut: $currentShortcut
                        )
                    }
                    
                    // Instructions for Globe Key
                    VStack(alignment: .leading, spacing: 8) {
                        Label("To use the 🌐 Globe Key", systemImage: "info.circle")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("1. Open System Settings → Keyboard\n2. Set \"Press 🌐 key to\" → \"Do Nothing\"\n3. Select \"🌐 Globe Key\" above")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Usage instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to Use")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionRow(number: 1, text: "Press and hold the shortcut keys")
                        InstructionRow(number: 2, text: "Speak clearly into your microphone")
                        InstructionRow(number: 3, text: "Release the keys to transcribe")
                        InstructionRow(number: 4, text: "Text is automatically pasted")
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - Shortcut Recorder View
struct ShortcutRecorderView: View {
    @Binding var isRecording: Bool
    @Binding var currentShortcut: String
    
    var body: some View {
        ZStack {
            if isRecording {
                ShortcutRecorderField(
                    isRecording: $isRecording,
                    currentShortcut: $currentShortcut
                )
            } else {
                // Display current shortcut
                HStack(spacing: 4) {
                    ForEach(parseShortcut(currentShortcut), id: \.self) { part in
                        if part == "+" {
                            Text("+")
                                .foregroundStyle(.secondary)
                        } else {
                            KeyCap(part)
                        }
                    }
                }
            }
        }
    }
    
    private func parseShortcut(_ shortcut: String) -> [String] {
        var parts: [String] = []
        var current = shortcut
        
        let modifiers = ["⌃", "⌥", "⇧", "⌘"]
        for mod in modifiers {
            if current.hasPrefix(mod) {
                parts.append(mod)
                parts.append("+")
                current = String(current.dropFirst())
            }
        }
        
        if !current.isEmpty {
            parts.append(current)
        }
        
        // Remove trailing +
        if parts.last == "+" {
            parts.removeLast()
        }
        
        return parts
    }
}

// MARK: - Shortcut Recorder Field (NSView wrapper)
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var currentShortcut: String
    
    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { keyCode, modifiers in
            HotkeyManager.shared.setHotkey(keyCode: keyCode, modifiers: modifiers)
            currentShortcut = HotkeyManager.shared.shortcutString
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }
    
    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        if isRecording {
            // Ensure the view becomes first responder and starts monitoring
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.startMonitoring()
            }
        } else {
            nsView.stopMonitoring()
        }
    }
}

class ShortcutRecorderNSView: NSView {
    var onShortcutRecorded: ((UInt16, CGEventFlags) -> Void)?
    var onCancel: (() -> Void)?
    nonisolated(unsafe) private var eventMonitor: Any?
    
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw recording indicator
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.fill()
        
        NSColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.stroke()
        
        // Draw text
        let text = "Type your shortcut..."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 32)
    }
    
    func startMonitoring() {
        guard eventMonitor == nil else { return }
        
        // Use local event monitor to capture key events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Escape to cancel
            if event.keyCode == UInt16(kVK_Escape) {
                self.onCancel?()
                return nil // Consume the event
            }
            
            // Get modifiers
            var modifiers: CGEventFlags = []
            if event.modifierFlags.contains(.control) {
                modifiers.insert(.maskControl)
            }
            if event.modifierFlags.contains(.option) {
                modifiers.insert(.maskAlternate)
            }
            if event.modifierFlags.contains(.shift) {
                modifiers.insert(.maskShift)
            }
            if event.modifierFlags.contains(.command) {
                modifiers.insert(.maskCommand)
            }
            
            // Require at least one modifier (unless it's a function key or Globe key)
            let isFunctionKey = (event.keyCode >= UInt16(kVK_F1) && event.keyCode <= UInt16(kVK_F20))
            let isGlobeKey = (event.keyCode == 63 || event.keyCode == 179)  // Fn or Globe key
            
            if modifiers.isEmpty && !isFunctionKey && !isGlobeKey {
                // Beep to indicate need modifier
                NSSound.beep()
                return nil
            }
            
            self.onShortcutRecorded?(event.keyCode, modifiers)
            return nil // Consume the event
        }
    }
    
    nonisolated func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    override func keyDown(with event: NSEvent) {
        // Handled by event monitor, but keep as fallback
    }
}

// MARK: - Preset Shortcut Button
struct PresetShortcutButton: View {
    let label: String
    let keyCode: UInt16
    let modifiers: CGEventFlags
    @Binding var currentShortcut: String
    var isRecommended: Bool = false
    
    var isSelected: Bool {
        HotkeyManager.shared.keyCode == keyCode &&
        HotkeyManager.shared.modifiers == modifiers
    }
    
    var body: some View {
        Button {
            HotkeyManager.shared.setHotkey(keyCode: keyCode, modifiers: modifiers)
            currentShortcut = HotkeyManager.shared.shortcutString
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                if isRecommended && !isSelected {
                    Text("★")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : (isRecommended ? Color.orange.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecommended && !isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct KeyCap: View {
    let key: String
    
    init(_ key: String) {
        self.key = key
    }
    
    var body: some View {
        Text(key)
            .font(.system(.body, design: .rounded, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Permissions Settings
struct PermissionsSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("LocalWhisper needs these permissions to work properly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Permission rows
                VStack(spacing: 0) {
                    PermissionRow(
                        icon: "mic.fill",
                        iconColor: .red,
                        title: "Microphone",
                        description: "Required to capture your voice for transcription",
                        isGranted: appState.permissionsService.microphoneGranted
                    ) {
                        appState.permissionsService.openMicrophoneSettings()
                    }
                    
                    Divider()
                        .padding(.leading, 56)
                    
                    PermissionRow(
                        icon: "accessibility",
                        iconColor: .blue,
                        title: "Accessibility",
                        description: "Required for global shortcuts and auto-paste",
                        isGranted: appState.permissionsService.accessibilityGranted
                    ) {
                        appState.permissionsService.requestAccessibilityPermission()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Refresh button
                Button {
                    Task {
                        await appState.permissionsService.checkAllPermissions()
                    }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding(24)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(16)
    }
}

// MARK: - Logs Settings
struct LogsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var records: [TranscriptionRecord] = []
    @State private var errorLogContent: String = ""
    @State private var selectedTab = 0
    @State private var searchText: String = ""
    @State private var languageFilter: String = ""
    @State private var expandedIDs: Set<UUID> = []

    private var filteredRecords: [TranscriptionRecord] {
        records.filter { r in
            let matchesSearch = searchText.isEmpty
                || r.text.localizedCaseInsensitiveContains(searchText)
                || r.appContext.localizedCaseInsensitiveContains(searchText)
            let matchesLang = languageFilter.isEmpty
                || r.detectedLanguages.contains(languageFilter)
            return matchesSearch && matchesLang
        }
    }

    private var allLanguagesUsed: [String] {
        Array(Set(records.flatMap { $0.detectedLanguages })).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logs")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Inspect transcription history (with detected languages) and runtime errors.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("", selection: $selectedTab) {
                    Text("Transcriptions").tag(0)
                    Text("Errors").tag(1)
                }
                .pickerStyle(.segmented)

                if selectedTab == 0 {
                    transcriptionsView
                } else {
                    errorsView
                }
            }
            .padding(24)
        }
        .task { await refresh() }
    }

    // MARK: Transcriptions

    private var statsBar: some View {
        let totalDuration = records.reduce(0.0) { $0 + $1.durationSeconds }
        let multilingualCount = records.filter { $0.mode == .multilingualVAD }.count
        let failedCount = records.filter { $0.errorMessage != nil }.count
        return HStack(spacing: 16) {
            stat("Total", "\(records.count)")
            stat("Duration", formatDuration(totalDuration))
            stat("Multilingual", "\(multilingualCount)")
            stat("Failed", "\(failedCount)", color: failedCount > 0 ? .red : nil)
            stat("Languages", "\(allLanguagesUsed.count)")
        }
    }

    private func stat(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var transcriptionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            statsBar

            HStack {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Language", selection: $languageFilter) {
                    Text("All languages").tag("")
                    ForEach(allLanguagesUsed, id: \.self) { lang in
                        Text("\(TranscriptionRecord.languageFlag(lang)) \(TranscriptionRecord.languageDisplayName(lang))").tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            HStack {
                Text("\(filteredRecords.count) of \(records.count) entries")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSWorkspace.shared.open(TranscriptionLogService.folderURL)
                } label: { Label("Open Folder", systemImage: "folder") }
                .buttonStyle(.bordered)
                Button {
                    Task { await exportTranscriptions() }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered)
                Button {
                    Task { await refresh() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
            }

            if filteredRecords.isEmpty {
                emptyState(records.isEmpty ? "No transcriptions yet" : "No results", icon: "waveform")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredRecords) { record in
                        TranscriptionRow(
                            record: record,
                            isExpanded: expandedIDs.contains(record.id),
                            onToggle: {
                                if expandedIDs.contains(record.id) {
                                    expandedIDs.remove(record.id)
                                } else {
                                    expandedIDs.insert(record.id)
                                }
                            },
                            onCopy: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(record.text, forType: .string)
                            },
                            onDelete: {
                                Task {
                                    await appState.transcriptionLogService.delete(id: record.id)
                                    await refresh()
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: Errors

    private var errorsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(ErrorLogService.logFolderURL)
                } label: { Label("Open Folder", systemImage: "folder") }
                .buttonStyle(.bordered)
                Button {
                    Task {
                        await appState.errorLogService.clear()
                        await refresh()
                    }
                } label: { Label("Clear", systemImage: "trash") }
                .buttonStyle(.bordered)
                Button {
                    Task { await refresh() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
            }

            if errorLogContent.isEmpty {
                emptyState("No errors logged", icon: "checkmark.seal")
            } else {
                ScrollView {
                    Text(errorLogContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 400)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
            }
        }
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }

    private func refresh() async {
        records = await appState.transcriptionLogService.readAll()
        errorLogContent = await appState.errorLogService.readTail(lineCount: 500)
    }

    private func exportTranscriptions() async {
        let text = await appState.transcriptionLogService.exportAsText()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "transcriptions.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Transcription Row

struct TranscriptionRow: View {
    let record: TranscriptionRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var formattedTimestamp: String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .medium
        return df.string(from: record.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formattedTimestamp)
                    .font(.caption).foregroundStyle(.secondary)

                if record.mode == .multilingualVAD {
                    Label("Multilingual", systemImage: "globe")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .cornerRadius(4)
                }

                ForEach(record.detectedLanguages, id: \.self) { lang in
                    Text("\(TranscriptionRecord.languageFlag(lang)) \(TranscriptionRecord.languageDisplayName(lang))")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                }

                Spacer()

                Text(record.appContext)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                Text("\(Int(record.durationSeconds))s · \(record.processingMs)ms")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let err = record.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(record.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : 3)
            }

            if isExpanded && record.segments.count > 1 {
                Divider()
                Text("Segments")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                ForEach(Array(record.segments.enumerated()), id: \.offset) { _, seg in
                    HStack(alignment: .top, spacing: 8) {
                        if let lang = seg.language {
                            Text(TranscriptionRecord.languageFlag(lang))
                                .frame(width: 24)
                        } else {
                            Text("·").frame(width: 24).foregroundStyle(.secondary)
                        }
                        Text(seg.text)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let dur = seg.durationSeconds {
                            Text(String(format: "%.1fs", dur))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if record.segments.count > 1 {
                    Button(action: onToggle) {
                        Label(isExpanded ? "Hide segments" : "Show \(record.segments.count) segments",
                              systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy text")

                Button(action: onDelete) {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete entry")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "waveform")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            
            // App name and version
            VStack(spacing: 4) {
                Text("LocalWhisper")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Description
            Text("Local voice-to-text transcription\npowered by WhisperKit")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            // Privacy badge
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("100% Offline • Your audio never leaves your device")
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.1))
            .cornerRadius(20)
            
            Spacer()
            
            // Credits
            VStack(spacing: 4) {
                Text("Built with WhisperKit by Argmax")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("© 2024 LocalWhisper")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
