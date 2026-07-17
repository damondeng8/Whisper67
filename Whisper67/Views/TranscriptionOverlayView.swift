import SwiftUI
import AppKit

// MARK: - View Model

@Observable
final class TranscriptionOverlayViewModel {
    enum PillState: Equatable {
        case listening, processing, success, error(String), message(String)
    }
    
    static let barCount = 20
    
    var state: PillState = .listening
    /// Center-weighted live bars (Wispr Flow style)
    var audioLevels: [CGFloat] = Array(repeating: 0.1, count: barCount)
    var providerName: String = ""
    var isSticky: Bool = false
    
    private var displayTimer: Timer?
    private var phase: Double = 0
    private var energy: CGFloat = 0          // gated loudness 0…1
    private var lastMicAt: Date = .distantPast
    private var texture: [Float] = []
    
    var statusText: String {
        switch state {
        case .listening: return isSticky ? "Sticky" : "Listening"
        case .processing: return "Transcribing…"
        case .success: return "Done"
        case .error(let m): return m
        case .message(let m): return m
        }
    }
    
    var isLiveListening: Bool { state == .listening }
    
    func startIdleAnimation() {
        displayTimer?.invalidate()
        // ~45 fps display loop for buttery bars
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            self?.tickDisplay()
        }
        if let displayTimer {
            RunLoop.main.add(displayTimer, forMode: .common)
        }
    }
    
    func stopIdleAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    private func tickDisplay() {
        phase += 0.11
        
        // Release energy when mic goes quiet
        if Date().timeIntervalSince(lastMicAt) > 0.1 {
            energy *= 0.88
        }
        
        let e: CGFloat
        switch state {
        case .listening:
            e = energy
        case .processing:
            // Soft center pulse while waiting on the model
            e = 0.16 + 0.06 * CGFloat(sin(phase * 1.6))
        default:
            e = 0
        }
        
        let target = WaveformShaper.bars(
            energy: e,
            count: Self.barCount,
            phase: phase,
            bandTexture: texture
        )
        audioLevels = WaveformShaper.smooth(
            current: audioLevels,
            target: target,
            attack: 0.42,
            release: 0.18
        )
    }
    
    /// Overall mic loudness (primary — drives the center-weighted wave)
    func updateAudioLevel(_ level: Float) {
        lastMicAt = Date()
        let gated = WaveformShaper.gateAndCompress(level)
        // Smooth energy so it doesn't jump
        let a: CGFloat = gated > energy ? 0.40 : 0.18
        energy = energy + (gated - energy) * a
    }
    
    /// Optional texture only (does not define the bar silhouette)
    func updateAudioBands(_ bands: [Float]) {
        lastMicAt = Date()
        texture = bands
        // If overall path is lagging, use peak of bands as a soft assist
        if let peak = bands.max() {
            let gated = WaveformShaper.gateAndCompress(peak * 0.85)
            if gated > energy {
                energy = energy + (gated - energy) * 0.25
            }
        }
    }
    
    func resetLevels() {
        energy = 0
        texture = []
        audioLevels = Array(repeating: 0.1, count: Self.barCount)
    }
    
    deinit { stopIdleAnimation() }
}

// MARK: - Wispr-style center wave

private struct AudioWaveformView: View {
    let levels: [CGFloat]
    let isActive: Bool
    let maxHeight: CGFloat
    
    var body: some View {
        HStack(alignment: .center, spacing: 2.2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                // Soft min height so the row always reads as a wave
                let h = max(3.5, level * maxHeight)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(isActive ? 0.88 : 0.32),
                                Color.primary.opacity(isActive ? 0.38 : 0.12)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 2.8, height: h)
            }
        }
        .frame(height: maxHeight)
    }
}

// MARK: - Pill content

struct TranscriptionOverlayView: View {
    @Bindable var viewModel: TranscriptionOverlayViewModel
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    static let pillWidth: CGFloat = 360
    static let pillHeight: CGFloat = 52
    
    var body: some View {
        HStack(spacing: 12) {
            // Soft status dot
            Circle()
                .fill(viewModel.state == .listening
                      ? Color.primary.opacity(0.75)
                      : Color.primary.opacity(0.35))
                .frame(width: 7, height: 7)
                .shadow(color: .primary.opacity(viewModel.state == .listening ? 0.25 : 0), radius: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.statusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                
                if case .listening = viewModel.state {
                    Text(viewModel.isSticky ? "⏎ send · esc cancel · drag" : "release ⌃ · drag")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .frame(width: 108, alignment: .leading)
            
            // Centerpiece waveform — Wispr-style center peak
            if viewModel.state == .listening || viewModel.state == .processing {
                AudioWaveformView(
                    levels: viewModel.audioLevels,
                    isActive: viewModel.state == .listening,
                    maxHeight: 26
                )
                .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 40)
            }
            
            if viewModel.state == .listening {
                HStack(spacing: 6) {
                    Button(action: onConfirm) {
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Send & paste")
                    
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.55))
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(width: Self.pillWidth, height: Self.pillHeight)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.06),
                                    Color.black.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onAppear { viewModel.startIdleAnimation() }
        .onDisappear { viewModel.stopIdleAnimation() }
    }
}

// MARK: - Clear hosting

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = .clear
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}

// MARK: - Panel

final class TranscriptionOverlayWindow: NSPanel {
    private static let positionKey = "whisper67.pillOrigin"
    
    private let viewModel = TranscriptionOverlayViewModel()
    private var hostingView: TransparentHostingView<TranscriptionOverlayView>!
    private var onCancel: () -> Void
    private var onConfirm: () -> Void
    
    init(onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        
        let w = TranscriptionOverlayView.pillWidth
        let h = TranscriptionOverlayView.pillHeight
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        isMovable = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isRestorable = false
        
        hostingView = TransparentHostingView(rootView: makeRoot())
        contentView = hostingView
        setContentSize(NSSize(width: w, height: h))
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in self?.savePosition() }
        
        restoreOrCenter()
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func makeRoot() -> TranscriptionOverlayView {
        TranscriptionOverlayView(
            viewModel: viewModel,
            onCancel: { [weak self] in self?.onCancel() },
            onConfirm: { [weak self] in self?.onConfirm() }
        )
    }
    
    func updateHandlers(onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        hostingView.rootView = makeRoot()
    }
    
    func show(providerName: String, sticky: Bool) {
        viewModel.providerName = providerName
        viewModel.isSticky = sticky
        viewModel.state = .listening
        viewModel.resetLevels()
        viewModel.startIdleAnimation()
        hostingView.rootView = makeRoot()
        let w = TranscriptionOverlayView.pillWidth
        let h = TranscriptionOverlayView.pillHeight
        setContentSize(NSSize(width: w, height: h))
        restoreOrCenter()
        orderFrontRegardless()
    }
    
    func setSticky(_ sticky: Bool) {
        DispatchQueue.main.async { self.viewModel.isSticky = sticky }
    }
    
    func hide() {
        viewModel.stopIdleAnimation()
        viewModel.resetLevels()
        orderOut(nil)
    }
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            if case .listening = self.viewModel.state {
                self.viewModel.updateAudioLevel(level)
            }
        }
    }
    
    func updateAudioBands(_ bands: [Float]) {
        DispatchQueue.main.async {
            if case .listening = self.viewModel.state {
                self.viewModel.updateAudioBands(bands)
            }
        }
    }
    
    func setProcessing() {
        DispatchQueue.main.async { self.viewModel.state = .processing }
    }
    
    func showSuccess() {
        DispatchQueue.main.async { self.viewModel.state = .success }
    }
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.viewModel.state = .error(message)
            self.orderFrontRegardless()
        }
    }
    
    func flashMessage(_ message: String) {
        DispatchQueue.main.async {
            self.viewModel.state = .message(message)
            self.orderFrontRegardless()
        }
    }
    
    private func restoreOrCenter() {
        if let data = UserDefaults.standard.data(forKey: Self.positionKey),
           let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: CGFloat],
           let x = d["x"], let y = d["y"] {
            setFrameOrigin(NSPoint(x: x, y: y))
            clampToScreen()
        } else {
            centerBottom()
        }
    }
    
    private func centerBottom() {
        guard let screen = NSScreen.main else { return }
        let s = frame.size
        setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - s.width / 2,
            y: screen.visibleFrame.minY + 72
        ))
        savePosition()
    }
    
    private func savePosition() {
        let o = frame.origin
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: ["x": o.x, "y": o.y],
            format: .binary,
            options: 0
        ) {
            UserDefaults.standard.set(data, forKey: Self.positionKey)
        }
    }
    
    private func clampToScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else { return }
        var o = frame.origin
        let v = screen.visibleFrame
        o.x = min(max(o.x, v.minX + 4), v.maxX - frame.width - 4)
        o.y = min(max(o.y, v.minY + 4), v.maxY - frame.height - 4)
        setFrameOrigin(o)
    }
}

// MARK: - Manager

@Observable
final class TranscriptionOverlayManager {
    static let shared = TranscriptionOverlayManager()
    private var overlayWindow: TranscriptionOverlayWindow?
    private var cancelHandler: (() -> Void)?
    private var confirmHandler: (() -> Void)?
    
    private init() {}
    
    func showOverlay(
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void = {},
        sticky: Bool = false,
        status: String = "Listening…",
        providerName: String = ""
    ) {
        cancelHandler = onCancel
        confirmHandler = onConfirm
        if overlayWindow == nil {
            overlayWindow = TranscriptionOverlayWindow(
                onCancel: { [weak self] in self?.cancelHandler?() },
                onConfirm: { [weak self] in self?.confirmHandler?() }
            )
        } else {
            overlayWindow?.updateHandlers(
                onCancel: { [weak self] in self?.cancelHandler?() },
                onConfirm: { [weak self] in self?.confirmHandler?() }
            )
        }
        overlayWindow?.show(providerName: providerName, sticky: sticky)
    }
    
    func setSticky(_ sticky: Bool) { overlayWindow?.setSticky(sticky) }
    func updateAudioLevel(_ level: Float) { overlayWindow?.updateAudioLevel(level) }
    func updateAudioBands(_ bands: [Float]) { overlayWindow?.updateAudioBands(bands) }
    func setProcessing() { overlayWindow?.setProcessing() }
    func showSuccess() { overlayWindow?.showSuccess() }
    
    func showError(_ message: String) {
        if overlayWindow == nil {
            overlayWindow = TranscriptionOverlayWindow(
                onCancel: { [weak self] in self?.hideOverlay() },
                onConfirm: {}
            )
        }
        overlayWindow?.showError(message)
    }
    
    func flashMessage(_ message: String) {
        if overlayWindow == nil {
            overlayWindow = TranscriptionOverlayWindow(
                onCancel: { [weak self] in self?.hideOverlay() },
                onConfirm: {}
            )
        }
        overlayWindow?.flashMessage(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hideOverlay()
        }
    }
    
    func hideOverlay() {
        overlayWindow?.hide()
        overlayWindow = nil
    }
}
