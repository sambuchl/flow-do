import SwiftUI

struct OrbView: View {
    @ObservedObject var model: FlowDoModel
    var diameter: CGFloat = 12
    var animationsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ember = Color(red: 0.78, green: 0.29, blue: 0.19)
    private var resting: Bool { model.paused || model.takingBreak }

    private var pinkDuration: TimeInterval {
        model.checkpointValue > 0
            ? min(3.2, Double(model.checkpointValue) * model.checkpointUnit.multiplier * 0.7) : 3.2
    }
    private var pulseActive: Bool {
        animationsEnabled && model.pulseEnabled && !resting && model.currentTask != nil && !reduceMotion
    }
    private var needsTimeline: Bool {
        animationsEnabled && !reduceMotion && (pulseActive || model.orbTransition != nil
            || model.achievementStartedAt != nil || model.completionStartedAt != nil)
    }

    private func color(for state: FlowState) -> Color {
        switch state {
        case .idle: return ember
        case .returning: return .yellow
        case .engaged: return .green
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !needsTimeline)) { _ in
            // All copies share monotonic timestamps, including the white pulse phase.
            indicator(at: ProcessInfo.processInfo.systemUptime)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: (resting ? Color.yellow : color(for: model.state)).opacity(0.25 + model.confidence * 0.45),
                radius: 1 + model.confidence * 3)
        .opacity(model.completionStartedAt != nil ? 1 :
                 (resting || model.currentTask == nil ? 0.45 : 0.75 + model.confidence * 0.25))
        .frame(width: diameter + 14, height: diameter + 10)
        .accessibilityLabel(model.completionStartedAt != nil ? "FlowDo, task complete" :
            "FlowDo, \(resting ? "taking a break" : model.state.label)")
    }

    @ViewBuilder
    private func indicator(at now: TimeInterval) -> some View {
        if let start = model.completionStartedAt, now - start < FlowDoModel.completionDuration {
            completion(elapsed: reduceMotion ? 4.0 : now - start)
        } else {
            ZStack {
                if resting {
                    Circle().fill(Color.yellow)
                } else if let transition = model.orbTransition, transition.progress(at: now) < 1, !reduceMotion {
                    whirlpool(transition: transition, now: now).clipShape(Circle())
                } else {
                    // A transition always settles on its explicit destination, never on
                    // a source color inferred from a different/expired animation marker.
                    let tint = color(for: model.orbTransition?.to ?? model.state)
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.65), tint],
                        center: .topLeading, startRadius: 0, endRadius: diameter))
                }
                if pulseActive {
                    Circle().fill(Color.white.opacity(PulseRhythm.whiteAmount(
                        at: now, epoch: model.pulseEpoch, bpm: model.pulseBPM)))
                }
                Circle().stroke(.white.opacity(0.4), lineWidth: 0.6)
                if let start = model.achievementStartedAt, now >= start, now - start < pinkDuration {
                    let progress = min(1, max(0, (now - start) / pinkDuration))
                    let alpha = reduceMotion ? 1 : min(1, min(progress / 0.25, (1 - progress) / 0.55))
                    // Pink celebrates in the halo; the center remains the current state.
                    Circle().stroke(Color.pink.opacity(alpha), lineWidth: max(1, diameter * 0.12))
                        .padding(-1)
                        .shadow(color: Color.pink.opacity(alpha * 0.7), radius: 2)
                }
            }
        }
    }

    private func whirlpool(transition: OrbTransition, now: TimeInterval) -> some View {
        let from = color(for: transition.from)
        let to = color(for: transition.to)
        let progress = transition.progress(at: now)
        let elapsed = max(0, now - transition.startedAt)
        return Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(ellipseIn: bounds), with: .color(from))
            let radius = min(size.width, size.height) / 2
            for arm in 0..<2 {
                var spiral = Path()
                for step in 0...80 {
                    let fraction = Double(step) / 80
                    let angle = fraction * .pi * 3 + elapsed * 1.8 + Double(arm) * .pi
                    let distance = radius * fraction
                    let point = CGPoint(x: size.width / 2 + cos(angle) * distance,
                                        y: size.height / 2 + sin(angle) * distance)
                    if step == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
                }
                context.stroke(spiral, with: .color(to.opacity(min(1, progress * 4))),
                    style: StrokeStyle(lineWidth: diameter * (0.02 + progress * 0.25), lineCap: .round))
            }
            context.fill(Path(ellipseIn: bounds), with: .color(to.opacity(pow(progress, 3))))
            context.fill(Path(ellipseIn: bounds), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.15), .clear]), center: .zero,
                startRadius: 0, endRadius: size.width))
        }
    }

    /// Authored shapes avoid emoji/platform variation: green → pink → ember heart.
    private func completion(elapsed: Double) -> some View {
        let elapsed = max(0, elapsed)
        let green = (0.20, 0.85, 0.38)
        let pink = (1.0, 0.20, 0.55)
        let darkRed = (0.42, 0.035, 0.055)
        let tint = elapsed < 1.6
            ? blend(green, pink, amount: elapsed / 1.6)
            : blend(pink, darkRed, amount: (elapsed - 1.6) / 2.2)
        let settle = min(1, max(0, (elapsed - 4.4) / 0.8))
        let fire = max(0, min(1, (3.8 - elapsed) / 1.6))
        return ZStack {
            Circle().fill(ember).opacity(settle * 0.45)
            ZStack {
                ForEach(0..<3) { index in
                    FlameShape()
                        .fill(LinearGradient(colors: [tint.opacity(0.15), tint, .orange.opacity(0.7)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: diameter * 0.28,
                               height: diameter * (0.42 + 0.04 * sin(elapsed * 4 + Double(index))))
                        .offset(x: CGFloat(index - 1) * diameter * 0.24, y: -diameter * 0.28)
                }.opacity(fire)
                HeartShape()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: diameter, height: diameter * 0.85)
                    .shadow(color: tint.opacity(0.7), radius: diameter * 0.18)
            }.opacity(1 - settle)
        }
    }

    private func blend(_ a: (Double, Double, Double), _ b: (Double, Double, Double), amount: Double) -> Color {
        let t = min(1, max(0, amount))
        return Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }
}

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.5, 0.96))
        path.addCurve(to: point(0.02, 0.28), control1: point(0.38, 0.78), control2: point(-0.06, 0.52))
        path.addCurve(to: point(0.5, 0.18), control1: point(0.08, -0.06), control2: point(0.4, -0.04))
        path.addCurve(to: point(0.98, 0.28), control1: point(0.6, -0.04), control2: point(0.92, -0.06))
        path.addCurve(to: point(0.5, 0.96), control1: point(1.06, 0.52), control2: point(0.62, 0.78))
        path.closeSubpath()
        return path
    }
}

private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX * 0.9, y: rect.midY * 0.5),
                      control2: CGPoint(x: rect.maxX * 1.2, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX - rect.width * 0.2, y: rect.maxY),
                      control2: CGPoint(x: rect.midX * 0.3, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
