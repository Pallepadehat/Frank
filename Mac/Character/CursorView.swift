import AppKit
import QuartzCore
import FrankShared

/// Everything on the overlay, as Core Animation layers so the GPU composites it smoothly every frame.
/// Layer space is y-up (bottom-left origin); the engine works y-down, so positions go through `layerPoint`.
final class CursorView: NSView {
    let engine = CursorEngine()

    private let root = CALayer()
    private let stringLayer = CAShapeLayer()
    private let trailLayer = CAShapeLayer()
    private let effects = CALayer()
    private let cursor = CALayer()
    private let body = TeardropLayer()
    private var eyes: [(socket: CALayer, white: CAShapeLayer, pupil: CAShapeLayer)] = []
    private let bubbles = CALayer()
    /// His speech bubble: a little cloud with a tail that points at his cursor (or down at the phone).
    private let speech = CAShapeLayer()
    private let speechFill = CAGradientLayer()
    private let speechFillMask = CAShapeLayer()
    private let speechBorder = CAShapeLayer()
    private let speechText = CATextLayer()
    private var speechSize = CGSize.zero
    private var speechBorn = 0.0

    private var builtArt: (side: CGFloat, glow: Bool, scale: CGFloat)?
    private var scale: CGFloat = 2
    private var samples: [(point: CGPoint, time: Double)] = []
    private var lastTwinkle = 0.0
    private var look = CGPoint(x: -0.7, y: -0.7)
    private var stringMid: CGPoint?
    private var stringMidVelocity = CGVector.zero
    private var activeBubbles: [(layer: CALayer, born: Double, life: Double)] = []

    /// The thing he's pointing at (overlay coordinates), so his bubble sits above it instead of covering it.
    var speechTarget: CGRect?

    /// What he's saying, shown in his speech bubble.
    var caption: String? {
        didSet { if caption != oldValue { layoutCaption() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = root
        wantsLayer = true
        root.masksToBounds = false

        stringLayer.fillColor = nil
        stringLayer.lineCap = .round
        stringLayer.lineWidth = 2.5
        stringLayer.strokeColor = NSColor(hex: Palette.berry1, alpha: 0.7).cgColor
        trailLayer.fillColor = NSColor(hex: Palette.berry2, alpha: 1).cgColor
        for l in [stringLayer, trailLayer, effects, cursor, bubbles, speech] { root.addSublayer(l) }

        cursor.anchorPoint = CGPoint(x: 0, y: 1)  // the tip: top-left corner in y-up space
        cursor.addSublayer(body)
        for _ in 0..<2 {
            let socket = CALayer()
            let white = CAShapeLayer()
            let pupil = CAShapeLayer()
            white.fillColor = NSColor.white.cgColor
            pupil.fillColor = NSColor(hex: Palette.ink).cgColor
            socket.addSublayer(white)
            socket.addSublayer(pupil)
            cursor.addSublayer(socket)
            eyes.append((socket, white, pupil))
        }

        // A clean white cloud with a faint blueberry tint at the bottom and a berry outline. No glow.
        speech.fillColor = NSColor.white.cgColor
        speech.opacity = 0
        speechFill.colors = [NSColor.white.cgColor, NSColor(hex: 0xEEF0FF).cgColor]
        speechFill.startPoint = CGPoint(x: 0.5, y: 1)
        speechFill.endPoint = CGPoint(x: 0.5, y: 0)
        speechFill.mask = speechFillMask
        speechBorder.fillColor = nil
        speechBorder.strokeColor = NSColor(hex: Palette.berry2, alpha: 1).cgColor
        speechBorder.lineWidth = 2.5
        speechBorder.lineJoin = .round
        speechText.isWrapped = true
        speechText.alignmentMode = .center
        for l in [speechFill, speechBorder, speechText] { speech.addSublayer(l) as Void }

        engine.onLand = { [weak self] point in self?.softLand(at: point) }
        engine.onLaunch = { [weak self] point in self?.puff(at: point) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        for l in [stringLayer, trailLayer, effects, bubbles] { l.frame = bounds }
        CATransaction.commit()
        layoutCaption()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        setScale(window?.backingScaleFactor ?? 2)
    }

    /// Pixel density for crisp drawing (also used by the preview renderer).
    func setScale(_ newScale: CGFloat) {
        scale = newScale
        for l in [root, stringLayer, trailLayer, cursor, body, speech, speechFill, speechFillMask, speechBorder, speechText] { l.contentsScale = scale }
        for eye in eyes { [eye.white, eye.pupil].forEach { $0.contentsScale = scale } }
        builtArt = nil
    }

    private func layerPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: bounds.height - p.y) }

    // MARK: Frame

    func step(dt: Double, now: Double, mouse: CGPoint) {
        engine.step(dt: dt, now: now, mouse: mouse, bounds: bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        render(now: now, dt: dt)
        CATransaction.commit()
    }

    private func buildArtIfNeeded() {
        let side = engine.size
        let glow = Settings.shared.glow
        if let art = builtArt, art.side == side, art.glow == glow, art.scale == scale { return }
        builtArt = (side, glow, scale)
        let k = side / 96
        cursor.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        body.side = side
        body.glow = glow
        body.contentsScale = scale
        body.frame = CGRect(x: -body.padding, y: -body.padding, width: side + body.padding * 2, height: side + body.padding * 2)
        body.setNeedsDisplay()
        body.displayIfNeeded()
        for (i, eye) in eyes.enumerated() {
            let d = 18 * k
            let x = (34 + CGFloat(i) * 24) * k, y = 40 * k  // design position, y down
            eye.socket.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            eye.socket.position = CGPoint(x: x + d / 2, y: side - (y + d / 2))
            eye.white.frame = eye.socket.bounds
            eye.white.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)
            let p = 9 * k
            eye.pupil.bounds = .zero
            eye.pupil.path = CGPath(ellipseIn: CGRect(x: -p / 2, y: -p / 2, width: p, height: p), transform: nil)
        }
    }

    private func render(now: Double, dt: Double) {
        buildArtIfNeeded()
        let settings = Settings.shared
        let k = engine.size / 96
        let visible = settings.showCursor

        // The cursor itself.
        cursor.position = layerPoint(CGPoint(x: engine.tip.x, y: engine.tip.y + engine.hover(now)))
        let squish = engine.pressScale(now)
        cursor.transform = CATransform3DConcat(CATransform3DMakeScale(squish, squish, 1),
                                               CATransform3DMakeRotation(-engine.angle, 0, 0, 1))
        cursor.opacity = Float(visible ? engine.opacity : 0)

        // Its eyes look where it's heading, and back at the tip when it stops. They blink now and then.
        let v = engine.velocity
        let speed = hypot(v.dx, v.dy)
        var wantLook = CGPoint(x: -0.7, y: -0.7)
        if speed > 90 {
            let a = -engine.angle
            let local = CGPoint(x: v.dx * cos(a) - v.dy * sin(a), y: v.dx * sin(a) + v.dy * cos(a))
            let n = max(hypot(local.x, local.y), 1)
            wantLook = CGPoint(x: local.x / n, y: local.y / n)
        }
        let follow = CGFloat(min(1, dt * 12))
        look = CGPoint(x: look.x + (wantLook.x - look.x) * follow, y: look.y + (wantLook.y - look.y) * follow)
        let blinking = now < engine.blinkUntil
        for eye in eyes {
            let d = 18 * k
            eye.pupil.position = CGPoint(x: d / 2 + look.x * 3.4 * k, y: d / 2 - look.y * 3.4 * k)
            eye.socket.transform = CATransform3DMakeScale(1, blinking ? 0.12 : 1, 1)
        }

        renderTrail(now: now, speed: speed, visible: visible)
        renderString(now: now, dt: dt, visible: visible)
        renderBubbles(now: now)
        renderSpeech(now: now)
    }

    private func renderTrail(now: Double, speed: CGFloat, visible: Bool) {
        let center = engine.bodyCenter
        samples.append((center, now))
        samples.removeAll { now - $0.time > 0.2 }
        guard visible, Settings.shared.trail == .comet, samples.count > 2, speed > 260 else {
            trailLayer.path = nil
            return
        }
        // A soft tapered comet tail along the path it just flew.
        let head = engine.size * 0.42
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<samples.count {
            let p = samples[i].point
            let prev = samples[max(0, i - 1)].point, next = samples[min(samples.count - 1, i + 1)].point
            var n = CGPoint(x: -(next.y - prev.y), y: next.x - prev.x)
            let length = max(hypot(n.x, n.y), 0.001)
            n = CGPoint(x: n.x / length, y: n.y / length)
            let w = head * pow(CGFloat(i) / CGFloat(samples.count - 1), 1.3) / 2
            left.append(layerPoint(CGPoint(x: p.x + n.x * w, y: p.y + n.y * w)))
            right.append(layerPoint(CGPoint(x: p.x - n.x * w, y: p.y - n.y * w)))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        trailLayer.path = path
        trailLayer.opacity = Float(min(1, (speed - 260) / 900) * 0.26 * engine.opacity)

        if speed > 900, now - lastTwinkle > 0.05 {
            lastTwinkle = now
            let jitter = CGPoint(x: .random(in: -10...10), y: .random(in: -10...10))
            twinkle(at: CGPoint(x: center.x + jitter.x, y: center.y + jitter.y))
        }
    }

    private func renderString(now: Double, dt: Double, visible: Bool) {
        guard visible, Settings.shared.trail == .string, engine.opacity > 0.02 else {
            stringLayer.path = nil
            stringMid = nil
            return
        }
        // Like a balloon string held by the phone: it trails behind with a little slack and sway.
        let from = CGPoint(x: bounds.width * Settings.shared.phonePosition, y: bounds.height + 4)
        let to = engine.bodyCenter
        let distance = hypot(to.x - from.x, to.y - from.y)
        let slack = max(0, 160 - distance * 0.12)
        let goal = CGPoint(x: (from.x + to.x) / 2 + CGFloat(sin(now * 1.3)) * 6, y: (from.y + to.y) / 2 + slack)
        var mid = stringMid ?? goal
        let k: CGFloat = 22, t = CGFloat(dt)
        stringMidVelocity.dx += (k * (goal.x - mid.x) - 2 * sqrt(k) * 0.55 * stringMidVelocity.dx) * t
        stringMidVelocity.dy += (k * (goal.y - mid.y) - 2 * sqrt(k) * 0.55 * stringMidVelocity.dy) * t
        mid.x += stringMidVelocity.dx * t
        mid.y += stringMidVelocity.dy * t
        stringMid = mid
        let control = CGPoint(x: 2 * mid.x - (from.x + to.x) / 2, y: 2 * mid.y - (from.y + to.y) / 2)
        let path = CGMutablePath()
        path.move(to: layerPoint(from))
        path.addQuadCurve(to: layerPoint(to), control: layerPoint(control))
        stringLayer.path = path
        stringLayer.opacity = Float(engine.opacity)
    }

    // MARK: Effects (fire and forget)

    private func addTransient(_ layer: CALayer, life: Double) {
        layer.contentsScale = scale
        effects.addSublayer(layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + life) { layer.removeFromSuperlayer() }
    }

    private func ring(at point: CGPoint, radius: CGFloat, color: UInt32, alpha: CGFloat, duration: Double) {
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = NSColor(hex: color, alpha: alpha).cgColor
        ring.lineWidth = 3.5
        ring.position = layerPoint(point)
        ring.opacity = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
        ring.add(group, forKey: "ring")
        addTransient(ring, life: duration + 0.05)
    }

    private func star(at point: CGPoint, radius: CGFloat, travel: CGVector, color: UInt32, duration: Double) {
        let star = CAShapeLayer()
        star.path = Teardrop.star(radius: radius)
        star.fillColor = NSColor(hex: color).cgColor
        star.position = layerPoint(point)
        star.opacity = 0
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: layerPoint(point))
        move.toValue = NSValue(point: layerPoint(CGPoint(x: point.x + travel.dx, y: point.y + travel.dy)))
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.3, 1)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.45, 1]
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.toValue = CGFloat.random(in: -2.5...2.5)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.4
        let group = CAAnimationGroup()
        group.animations = [move, fade, spin, shrink]
        group.duration = duration
        star.add(group, forKey: "star")
        addTransient(star, life: duration + 0.05)
    }

    private func twinkle(at point: CGPoint) {
        star(at: point, radius: .random(in: 3...5.5), travel: CGVector(dx: .random(in: -8...8), dy: .random(in: 6...18)),
             color: [Palette.berry1, Palette.berry2].randomElement()!, duration: 0.5)
    }

    /// Landing on something it's pointing at: a soft ring and a tiny nod.
    private func softLand(at point: CGPoint) {
        engine.press(depth: 0.05)
        ring(at: point, radius: 30, color: Palette.berry2, alpha: 0.55, duration: 0.7)
    }

    /// Popping out of (or diving back into) the phone at the bottom edge.
    private func puff(at point: CGPoint) {
        guard Settings.shared.showCursor else { return }
        ring(at: point, radius: 26, color: Palette.berry1, alpha: 0.6, duration: 0.55)
        for i in 0..<3 {
            let dx = CGFloat(i - 1) * 14
            star(at: CGPoint(x: point.x + dx, y: point.y - 4), radius: 4, travel: CGVector(dx: dx * 0.6, dy: -28),
                 color: Palette.berry1, duration: 0.6)
        }
    }

    /// A real click: a firm squish, a ring and a little burst of stars.
    func clickEffect(at point: CGPoint, right: Bool = false) {
        engine.press(depth: 0.14)
        ring(at: point, radius: 38, color: right ? Palette.berry3 : Palette.berry2, alpha: 0.85, duration: 0.65)
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * 2 * .pi + .random(in: -0.25...0.25)
            let distance = CGFloat.random(in: 34...58)
            star(at: point, radius: .random(in: 4...7), travel: CGVector(dx: cos(a) * distance, dy: sin(a) * distance),
                 color: [Palette.berry1, Palette.berry2, Palette.berry3].randomElement()!, duration: 0.55)
        }
    }

    /// A typed character floating up from the cursor, so you can see him typing.
    func typedEffect(_ text: String) {
        guard Settings.shared.showCursor, engine.opacity > 0.1 else { return }
        engine.press(depth: 0.035)
        for (i, ch) in text.enumerated() where !ch.isWhitespace {
            let glyph = CATextLayer()
            glyph.string = NSAttributedString(string: String(ch), attributes: [
                .font: Fonts.display(22),
                .foregroundColor: NSColor(hex: Palette.berry3),
                .strokeColor: NSColor.white,
                .strokeWidth: -3.5,
            ])
            glyph.alignmentMode = .center
            glyph.bounds = CGRect(x: 0, y: 0, width: 28, height: 30)
            let start = CGPoint(x: engine.tip.x + engine.size * 0.55 + CGFloat(i) * 6, y: engine.tip.y - 6)
            glyph.position = layerPoint(start)
            glyph.opacity = 0
            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: layerPoint(start))
            rise.toValue = NSValue(point: layerPoint(CGPoint(x: start.x + .random(in: -12...16), y: start.y - 46)))
            rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.12, 0.55, 1]
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.1
            shrink.toValue = 0.75
            let group = CAAnimationGroup()
            group.animations = [rise, fade, shrink]
            group.duration = 0.9
            glyph.add(group, forKey: "glyph")
            addTransient(glyph, life: 0.95)
        }
    }

    /// A little label that pops up next to the cursor, like "⌘T" or "Opening Safari".
    func bubble(_ text: String, life: Double = 1.4) {
        guard Settings.shared.showCursor else { return }
        let label = CATextLayer()
        let attributed = NSAttributedString(string: text, attributes: [
            .font: Fonts.display(19),
            .foregroundColor: NSColor.white,
        ])
        label.string = attributed
        label.contentsScale = scale
        label.alignmentMode = .center
        let size = attributed.size()
        let box = CALayer()
        box.backgroundColor = NSColor(hex: Palette.ink, alpha: 0.92).cgColor
        box.borderColor = NSColor(hex: Palette.berry2, alpha: 0.9).cgColor
        box.borderWidth = 2
        box.cornerRadius = 14
        box.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 28, height: ceil(size.height) + 14)
        label.frame = box.bounds.insetBy(dx: 14, dy: 7)
        box.addSublayer(label)
        box.contentsScale = scale
        box.opacity = 0
        // The newest bubble replaces any older one.
        for old in activeBubbles { old.layer.removeFromSuperlayer() }
        activeBubbles = []
        bubbles.addSublayer(box)
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.4
        pop.toValue = 1
        pop.damping = 11
        pop.initialVelocity = 6
        pop.duration = pop.settlingDuration
        box.add(pop, forKey: "pop")
        activeBubbles.append((box, CACurrentMediaTime(), life))
    }

    private func renderBubbles(now: Double) {
        guard !activeBubbles.isEmpty else { return }
        let anchor: CGPoint
        if engine.opacity > 0.1 {
            anchor = CGPoint(x: engine.tip.x + engine.size * 1.05, y: engine.tip.y - engine.size * 0.1)
        } else {
            anchor = CGPoint(x: bounds.width * Settings.shared.phonePosition, y: bounds.height - engine.size * 1.3)
        }
        activeBubbles.removeAll { bubble in
            let age = now - bubble.born
            if age > bubble.life {
                bubble.layer.removeFromSuperlayer()
                return true
            }
            var point = anchor
            let width = bubble.layer.bounds.width
            if point.x + width > bounds.width - 12 { point.x = engine.tip.x - width - engine.size * 0.3 }
            bubble.layer.position = layerPoint(CGPoint(x: point.x + width / 2, y: point.y - CGFloat(min(age, 0.3)) * 20))
            let fadeIn = min(1, age / 0.12), fadeOut = min(1, (bubble.life - age) / 0.3)
            bubble.layer.opacity = Float(min(fadeIn, fadeOut))
            return false
        }
    }

    // MARK: Speech bubble

    private static let speechPad = CGSize(width: 24, height: 15)
    private static let tailLength: CGFloat = 18

    private func layoutCaption() {
        guard let caption, !caption.isEmpty, bounds.width > 0 else {
            if speech.opacity > 0 {
                // Shrink away with a little pop.
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = speech.presentation()?.opacity ?? 1
                fade.toValue = 0
                let shrink = CABasicAnimation(keyPath: "transform.scale")
                shrink.fromValue = 1
                shrink.toValue = 0.85
                let group = CAAnimationGroup()
                group.animations = [fade, shrink]
                group.duration = 0.22
                group.timingFunction = CAMediaTimingFunction(name: .easeIn)
                speech.add(group, forKey: "fade")
                speech.opacity = 0
            }
            speechSize = .zero
            return
        }
        // Longer replies get a slightly smaller font and a wider bubble, so it never turns into a tower.
        let length = caption.count
        let fontSize: CGFloat = length <= 50 ? 21 : length <= 110 ? 19 : 17
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 1.5
        let text = NSAttributedString(string: caption, attributes: [
            .font: Fonts.display(fontSize),
            .foregroundColor: NSColor(hex: Palette.ink),
            .paragraphStyle: style,
        ])
        // Aim for a cosy, balanced shape (a couple of lines) rather than one long strip.
        let maxWidth = min(bounds.width * 0.5, 580, max(240, sqrt(Double(length)) * 50))
        let size = text.boundingRect(with: CGSize(width: maxWidth, height: 800),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let pad = Self.speechPad
        let newSize = CGSize(width: max(ceil(size.width) + pad.width * 2, 70), height: ceil(size.height) + pad.height * 2)
        let appearing = speechSize == .zero || speech.opacity == 0
        speechSize = newSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        speechText.string = text
        CATransaction.commit()
        if appearing {
            speechBorn = CACurrentMediaTime()
            speech.removeAnimation(forKey: "fade")
            speech.opacity = 1
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.55
            pop.toValue = 1
            pop.damping = 12
            pop.stiffness = 260
            pop.initialVelocity = 4
            pop.duration = pop.settlingDuration
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.duration = 0.12
            speech.add(pop, forKey: "pop")
            speech.add(fadeIn, forKey: "fadeIn")
        }
    }

    /// Follows his cursor every frame: above the thing he's pointing at (or below his cursor when there's
    /// no room up there), otherwise just above the phone.
    private func renderSpeech(now: Double) {
        guard speechSize != .zero else { return }
        let size = speechSize
        let tail = Self.tailLength
        let margin: CGFloat = 14
        let pointing = engine.opacity > 0.1 && !engine.isHome
        var target: CGPoint  // where the tail points, y down
        var origin: CGPoint  // bubble top-left, y down
        var tailUp = false
        // Below the cursor (which hangs down-right from its tip), for when there's no room above.
        let belowCursor = CGPoint(x: engine.tip.x + engine.size * 0.5, y: engine.tip.y + engine.size * 1.35)
        if pointing {
            let thing = speechTarget ?? CGRect(x: engine.tip.x - 12, y: engine.tip.y - 30, width: 24, height: 24)
            target = CGPoint(x: thing.midX, y: thing.minY - 10)
            origin = CGPoint(x: target.x - size.width / 2, y: target.y - tail - size.height)
            if origin.y < margin {
                target = belowCursor
                origin = CGPoint(x: target.x - size.width / 2, y: target.y + tail)
                tailUp = true
            }
        } else {
            target = CGPoint(x: bounds.width * Settings.shared.phonePosition, y: bounds.height - engine.size * 0.9)
            origin = CGPoint(x: target.x - size.width / 2, y: target.y - tail - size.height)
        }
        origin.x = min(max(origin.x, margin), bounds.width - size.width - margin)
        origin.y = min(max(origin.y, margin), bounds.height - size.height - margin)
        let float = CGFloat(sin((now - speechBorn) * 2.2)) * 2  // a gentle bob
        origin.y += float
        target.y += float * 0.5

        // Layer space is y-up.
        let frame = CGRect(x: origin.x, y: bounds.height - origin.y - size.height, width: size.width, height: size.height)
        speech.bounds = CGRect(origin: .zero, size: size)
        speech.position = CGPoint(x: frame.midX, y: frame.midY)
        speechFill.frame = speech.bounds
        speechBorder.frame = speech.bounds
        speechFillMask.frame = speech.bounds
        speechText.frame = speech.bounds.insetBy(dx: Self.speechPad.width, dy: Self.speechPad.height - 1)

        // The tail starts on the bottom (or top) edge, as close under the target as the corners allow,
        // and leans toward it.
        let w = size.width, h = size.height
        let r = min(24, h / 2)
        let half: CGFloat = 13
        let localX = target.x - origin.x
        let baseX = min(max(localX, r + half + 2), w - r - half - 2)
        let lean = min(max(localX - baseX, -tail * 1.4), tail * 1.4)
        let tipY: CGFloat = tailUp ? h + tail : -tail
        let tip = CGPoint(x: baseX + lean, y: tipY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        if !tailUp {
            path.addLine(to: CGPoint(x: baseX - half, y: 0))
            path.addCurve(to: tip, control1: CGPoint(x: baseX - half * 0.3, y: 0), control2: CGPoint(x: tip.x - 1, y: tipY * 0.5))
            path.addCurve(to: CGPoint(x: baseX + half, y: 0), control1: CGPoint(x: tip.x + 2, y: tipY * 0.45), control2: CGPoint(x: baseX + half * 0.4, y: 0))
        }
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
        if tailUp {
            path.addLine(to: CGPoint(x: baseX + half, y: h))
            path.addCurve(to: tip, control1: CGPoint(x: baseX + half * 0.3, y: h), control2: CGPoint(x: tip.x + 1, y: h + tail * 0.5))
            path.addCurve(to: CGPoint(x: baseX - half, y: h), control1: CGPoint(x: tip.x - 2, y: h + tail * 0.45), control2: CGPoint(x: baseX - half * 0.4, y: h))
        }
        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.closeSubpath()
        speech.path = path
        speechFillMask.path = path
        speechBorder.path = path
    }
}
