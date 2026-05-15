import SwiftUI
import AppKit

/// Borderless floating panel shown while recording. Renders a live waveform
/// from `AppState.recentAudioLevels`. Created lazily and reused across recordings.
@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard let appState else { return }
        if panel == nil {
            let view = RecordingOverlayView()
                .environmentObject(appState)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 60)

            let p = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.hasShadow = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.ignoresMouseEvents = true
            p.contentView = hosting

            // Position near the bottom-center of the main screen
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let x = visible.midX - hosting.frame.width / 2
                let y = visible.minY + 80
                p.setFrameOrigin(NSPoint(x: x, y: y))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 1.0 : 0.4)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse.toggle() }

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Waveform(levels: appState.recentAudioLevels)
                .frame(width: 110, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.78))
        )
        .padding(2)
    }

    @State private var pulse = false

    private var label: String {
        switch appState.transcriptionState {
        case .recording: return "Listening"
        case .transcribing: return "Transcribing…"
        default: return ""
        }
    }
}

/// Simple bar-chart waveform for a sliding window of peak levels.
struct Waveform: View {
    let levels: [Float]
    private let barCount = 28

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = sample(at: i)
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(2, (geo.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)),
                               height: max(2, CGFloat(level) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func sample(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0.05 }
        // Map bar index to the last `barCount` values in the buffer.
        let start = max(0, levels.count - barCount)
        let pos = start + index
        guard pos < levels.count else { return 0.05 }
        // Boost visibility — raw mic levels rarely exceed ~0.3.
        return min(1.0, levels[pos] * 3.0 + 0.05)
    }
}
