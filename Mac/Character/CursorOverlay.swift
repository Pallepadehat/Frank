import AppKit
import QuartzCore
import FrankShared

/// A click-through, transparent window over the whole main screen that shows the cursor.
final class CursorOverlay: NSObject {
    let view = CursorView(frame: .zero)
    private var window: NSWindow?
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0

    /// Called every frame with the face the phone should show.
    var onFace: ((FaceState) -> Void)?

    var mode: CursorMode {
        get { view.engine.mode }
        set { view.engine.setMode(newValue) }
    }

    /// Where the cursor rests when nobody is pointing: tucked away with eyes on your mouse, or parked above the phone.
    var idleMode: CursorMode { Settings.shared.followMouse ? .following : .docked }

    func goHome() { mode = idleMode }

    func start() {
        mode = idleMode
        makeWindow()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.makeWindow()
        }
        // Driven by the display itself, so every frame is evenly paced.
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func talkTest(seconds: Double = 3) {
        view.engine.talkUntil = CACurrentMediaTime() + seconds
    }

    private func makeWindow() {
        guard let screen = NSScreen.screens.first else { return }
        if let window {
            window.setFrame(screen.frame, display: true)
            return
        }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let window else { return }
        let now = link.targetTimestamp
        let dt = lastTime == 0 ? 1.0 / 60 : min(max(now - lastTime, 1.0 / 480), 1.0 / 20)
        lastTime = now
        let m = NSEvent.mouseLocation
        let f = window.frame
        view.step(dt: dt, now: now, mouse: CGPoint(x: m.x - f.minX, y: f.maxY - m.y))
        onFace?(view.engine.face(in: view.bounds.size, now: now))
    }
}
