import AppKit
import QuartzCore
import FrankShared

/// Where the big character cursor wants to be.
enum CursorMode: Equatable {
    /// Parked at the bottom edge of the screen, peeking up above the phone.
    case docked
    /// Tucked out of sight below the screen; the phone's eyes follow your own mouse instead.
    case following
    /// Flew to a spot and stays there.
    case pinned(CGPoint)
}

/// How the cursor's path shows while it flies.
enum PointerTrail: String, CaseIterable {
    case comet, string, none

    var title: String {
        switch self {
        case .comet: return "Comet Trail"
        case .string: return "String to the Phone"
        case .none: return "No Trail"
        }
    }
}

/// A CSS-style cubic-bezier timing curve: maps time (0…1) to progress (0…1).
struct TimingCurve {
    let x1: Double, y1: Double, x2: Double, y2: Double

    /// Starts gently, then arrives with a long, soft deceleration.
    static let launch = TimingCurve(x1: 0.42, y1: 0, x2: 0.22, y2: 1)
    /// Keeps the speed it already had (for a change of plans mid-flight), then settles the same way.
    static let redirect = TimingCurve(x1: 0.25, y1: 0.25, x2: 0.22, y2: 1)
    /// Even and deliberate, for drags.
    static let steady = TimingCurve(x1: 0.42, y1: 0, x2: 0.38, y2: 1)

    private func coordinate(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }

    private func parameter(for x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = coordinate(t, x1, x2) - x
            if abs(error) < 1e-7 { return t }
            let d = derivative(t, x1, x2)
            if abs(d) < 1e-7 { break }
            t -= error / d
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<40 {
            let value = coordinate(t, x1, x2)
            if abs(value - x) < 1e-7 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return t
    }

    func value(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return coordinate(parameter(for: x), y1, y2)
    }

    /// How fast progress changes with time at `x`.
    func rate(at x: Double) -> Double {
        let t = parameter(for: min(max(x, 0), 1))
        let dx = derivative(t, x1, x2), dy = derivative(t, y1, y2)
        return dx > 1e-7 ? dy / dx : 0
    }
}

/// One planned trip: a smooth cubic curve walked with an easing curve.
private struct Flight {
    let from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint
    let start: Double, duration: Double
    let timing: TimingCurve
    /// It was sent to point at something (not heading home).
    let pointing: Bool
    var landed = false

    func progress(_ now: Double) -> Double {
        duration <= 0 ? 1 : min(1, max(0, (now - start) / duration))
    }

    func position(_ e: CGFloat) -> CGPoint {
        let u = 1 - e
        let a = u * u * u, b = 3 * u * u * e, c = 3 * u * e * e, d = e * e * e
        return CGPoint(x: a * from.x + b * c1.x + c * c2.x + d * to.x,
                       y: a * from.y + b * c1.y + c * c2.y + d * to.y)
    }

    func tangent(_ e: CGFloat) -> CGPoint {
        let u = 1 - e
        let a = 3 * u * u, b = 6 * u * e, c = 3 * e * e
        return CGPoint(x: a * (c1.x - from.x) + b * (c2.x - c1.x) + c * (to.x - c2.x),
                       y: a * (c1.y - from.y) + b * (c2.y - c1.y) + c * (to.y - c2.y))
    }
}

/// Where the cursor is and how it moves. Coordinates are top-left origin, y down, in points.
final class CursorEngine {
    private(set) var mode: CursorMode = .following
    private(set) var tip = CGPoint(x: -1000, y: -1000)
    private(set) var velocity = CGVector.zero
    private(set) var angle: CGFloat = .pi / 4
    private var angleVelocity: CGFloat = 0
    private(set) var opacity: CGFloat = 0
    private var flight: Flight?
    private var placed = false
    private(set) var bounds = CGSize(width: 1440, height: 900)
    /// Drags move slower and in a straight, steady line.
    var dragging = false

    /// Called when a flight lands on a spot it was sent to point at.
    var onLand: ((CGPoint) -> Void)?
    /// Called when it pops out of the phone or dives back in (a point on the bottom edge).
    var onLaunch: ((CGPoint) -> Void)?
    private(set) var landedAt = -10.0
    private var pressStart = -10.0
    private var pressDepth: CGFloat = 0

    var talkUntil = 0.0
    /// Set while he's listening, thinking or talking.
    var brainMood: Mood?
    /// Where the phone's eyes should look instead of at the cursor (e.g. at you while he listens).
    var gazeOverride: CGPoint?
    /// True while he's awake and talking with you (no dozing off then).
    var awake = false
    private var mouse = CGPoint.zero
    private var lastMouseMove = CACurrentMediaTime()
    /// Live voice loudness, 0…1.
    var talkLevel: () -> Double = { 0 }
    private(set) var blinkUntil = 0.0
    private var nextBlink = CACurrentMediaTime() + 3

    let settings = Settings.shared
    var size: CGFloat { CGFloat(settings.cursorSize) }

    func setMode(_ newMode: CursorMode) { mode = newMode }

    var isHome: Bool {
        if case .pinned = mode { return false }
        return true
    }

    /// Where the phone sits, just below the bottom edge of the screen.
    func phonePoint(in b: CGSize) -> CGPoint {
        CGPoint(x: b.width * settings.phonePosition, y: b.height + b.height * 0.18)
    }

    /// Peeking up from the bottom edge, right above the phone.
    func dockPoint(in b: CGSize) -> CGPoint {
        CGPoint(x: b.width * settings.phonePosition, y: b.height - size * 0.42)
    }

    /// Just below the bottom edge, out of sight, as if tucked into the phone.
    func tuckedPoint(in b: CGSize) -> CGPoint {
        CGPoint(x: b.width * settings.phonePosition, y: b.height + size * 0.35)
    }

    private func goal() -> CGPoint {
        switch mode {
        case .docked: return dockPoint(in: bounds)
        case .following: return tuckedPoint(in: bounds)
        case .pinned(let p): return p
        }
    }

    /// Seconds until the current trip arrives.
    func timeToArrive(_ now: Double) -> Double {
        guard let flight else { return 0 }
        return max(0, flight.start + flight.duration - now)
    }

    /// A little squish toward the tip, like pressing a button.
    func press(depth: CGFloat, at now: Double = CACurrentMediaTime()) {
        pressStart = now
        pressDepth = depth
    }

    func step(dt: Double, now: Double, mouse: CGPoint, bounds: CGSize) {
        self.bounds = bounds
        if hypot(mouse.x - self.mouse.x, mouse.y - self.mouse.y) > 1.5 { lastMouseMove = now }
        self.mouse = mouse
        if !placed {
            tip = tuckedPoint(in: bounds)
            placed = true
        }

        let target = goal()
        let needsPlan: Bool
        if let flight {
            needsPlan = hypot(flight.to.x - target.x, flight.to.y - target.y) > 0.5
        } else {
            needsPlan = hypot(tip.x - target.x, tip.y - target.y) > 0.5
        }
        if needsPlan { plan(to: target, now: now) }
        advance(now)

        // Fades in the moment it leaves home; in follow mode it fades out once it has tucked itself away.
        let settled = (flight?.progress(now) ?? 1) >= 1
        let wantOpacity: CGFloat = (mode == .following && settled) ? 0 : 1
        let rate = wantOpacity > opacity ? 12.0 : 6.0
        opacity += (wantOpacity - opacity) * CGFloat(min(1, dt * rate))

        // Upright like a normal cursor while out and about (tipped up when parked), leaning a touch into the motion.
        let lean = max(-0.2, min(0.2, velocity.dx / 2800))
        let targetAngle: CGFloat = (isHome ? .pi / 4 : 0) + lean
        let k: CGFloat = 24
        let t = CGFloat(dt)
        angleVelocity += (k * (targetAngle - angle) - 2 * sqrt(k) * angleVelocity) * t
        angle += angleVelocity * t

        if now > nextBlink {
            blinkUntil = now + 0.13
            nextBlink = now + .random(in: 2.5...6)
        }
    }

    /// Plans a natural-looking trip: a gentle curve, timed like a real hand movement (longer trips take
    /// a bit longer, but not proportionally), with a smooth start and a long, soft landing.
    private func plan(to goal: CGPoint, now: Double) {
        let from = tip
        let dx = goal.x - from.x, dy = goal.y - from.y
        let distance = hypot(dx, dy)
        let pointing = !isHome
        let dock = dockPoint(in: bounds)
        let fromHome = hypot(from.x - dock.x, from.y - dock.y) < size * 1.2 || from.y > bounds.height - 2
        guard distance > 0.5 else {
            flight = Flight(from: from, c1: from, c2: goal, to: goal, start: now, duration: 0, timing: .launch, pointing: pointing)
            return
        }

        var duration = min(1.2, max(0.45, 0.4 + 0.12 * log2(1 + Double(distance) / 24)))
        if dragging { duration = min(1.6, max(0.6, duration * 1.45)) }

        let direction = CGPoint(x: dx / distance, y: dy / distance)
        var normal = CGPoint(x: -direction.y, y: direction.x)
        if abs(direction.x) > 0.4 {
            if normal.y > 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }  // sideways trips bow gently upward
        } else {
            let towardMiddle: CGFloat = bounds.width / 2 - (from.x + goal.x) / 2 >= 0 ? 1 : -1
            if normal.x * towardMiddle < 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }  // vertical trips bow toward the middle
        }
        let bow = dragging ? 0 : min(distance * 0.1, 70) * 0.75
        let reach = distance * 0.3
        let c2 = CGPoint(x: goal.x - direction.x * reach + normal.x * bow,
                         y: goal.y - direction.y * reach + normal.y * bow)

        let speed = hypot(velocity.dx, velocity.dy)
        let c1: CGPoint
        let timing: TimingCurve
        if speed > 60 {
            // A change of plans mid-flight: carry on from the current speed and heading, no kink.
            var carry = CGPoint(x: velocity.dx * CGFloat(duration) / 3, y: velocity.dy * CGFloat(duration) / 3)
            let length = hypot(carry.x, carry.y)
            if length > distance * 0.6 {
                carry = CGPoint(x: carry.x / length * distance * 0.6, y: carry.y / length * distance * 0.6)
            }
            c1 = CGPoint(x: from.x + carry.x, y: from.y + carry.y)
            timing = .redirect
        } else {
            c1 = CGPoint(x: from.x + direction.x * reach + normal.x * bow,
                         y: from.y + direction.y * reach + normal.y * bow)
            timing = dragging ? .steady : .launch
        }
        flight = Flight(from: from, c1: c1, c2: c2, to: goal, start: now, duration: duration, timing: timing, pointing: pointing)
        if pointing && fromHome { onLaunch?(CGPoint(x: dock.x, y: bounds.height)) }
    }

    private func advance(_ now: Double) {
        guard var flight else {
            velocity = .zero
            return
        }
        let p = flight.progress(now)
        let e = CGFloat(flight.timing.value(at: p))
        tip = flight.position(e)
        if p >= 1 {
            velocity = .zero
            if !flight.landed {
                flight.landed = true
                self.flight = flight
                if flight.pointing {
                    landedAt = now
                    onLand?(tip)
                } else if mode == .following {
                    onLaunch?(CGPoint(x: tip.x, y: bounds.height))
                }
            }
        } else {
            let rate = CGFloat(flight.timing.rate(at: p) / flight.duration)
            let d = flight.tangent(e)
            velocity = CGVector(dx: d.x * rate, dy: d.y * rate)
        }
    }

    /// Scale for the press squish: a quick press, then a spring back with the tiniest rebound.
    func pressScale(_ now: Double) -> CGFloat {
        let t = now - pressStart
        guard t >= 0, t < 0.42 else { return 1 }
        if t < 0.12 { return 1 - pressDepth * CGFloat(sin(t / 0.12 * .pi / 2)) }
        let r = (t - 0.12) / 0.3
        return 1 - pressDepth * CGFloat(cos(r * .pi * 1.5) * exp(-r * 3.2))
    }

    /// A slow, gentle hover while it holds a point (eased in so it never jumps).
    func hover(_ now: Double) -> CGFloat {
        guard !isHome, (flight?.progress(now) ?? 1) >= 1 else { return 0 }
        let since = now - landedAt
        let amount = CGFloat(min(1, max(0, (since - 0.35) / 0.6)))
        return CGFloat(sin(since * 2.4)) * 1.6 * amount
    }

    var bodyCenter: CGPoint {
        let r = size * 0.5 * sqrt(2)
        return CGPoint(x: tip.x + cos(angle + .pi / 4) * r, y: tip.y + sin(angle + .pi / 4) * r)
    }

    /// What the phone's face should do: look at the cursor (or at your mouse in follow mode).
    func face(in bounds: CGSize, now: Double) -> FaceState {
        let phone = phonePoint(in: bounds)
        let c = mode == .following ? mouse : bodyCenter
        var gx = max(-1, min(1, (c.x - phone.x) / (bounds.width * 0.5)))
        var gy = -max(0.15, min(1, (phone.y - c.y) / (bounds.height * 1.1)))
        if let g = gazeOverride { gx = g.x; gy = g.y }

        let testing = now < talkUntil
        let talk = testing ? 0.5 + 0.5 * sin(now * 19) * sin(now * 7.3) : talkLevel()
        var mood = settings.mood
        if let brainMood {
            mood = brainMood
        } else if testing {
            mood = .talking
        } else if case .pinned = mode, mood == .listening {
            mood = .pointing
        } else if mode == .following, !awake, mood == .listening {
            // Your mouse sat still: he gets drowsy after 5 seconds and dozes off after 15.
            let idle = now - lastMouseMove
            if idle > 15 { mood = .resting } else if idle > 5 { mood = .sleepy }
        }
        return FaceState(gazeX: gx, gazeY: gy, mood: mood, talk: talk)
    }
}
