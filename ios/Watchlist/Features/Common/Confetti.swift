import NucleusUI
import SwiftUI

/// A burst of confetti from the bottom of the screen whenever a title becomes watched,
/// in Nucleus colours. Drawn in one canvas, so it costs nothing while idle.
struct Confetti: View {
    let trigger: Int
    @State private var bursts: [Burst] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [0x6366F1, 0xA78BFA, 0x34D399, 0xFBBF24, 0xF472B6].map { Color(hex: $0) }
    private static let lifetime: TimeInterval = 2.4

    struct Piece {
        let velocity: CGVector
        let spin: Double
        let color: Color
        let size: CGSize
        let wobble: Double
    }

    struct Burst: Identifiable {
        let id = UUID()
        let start = Date()
        let pieces: [Piece]
    }

    var body: some View {
        TimelineView(.animation(paused: bursts.isEmpty)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for burst in bursts {
                    let t = now.timeIntervalSince(burst.start)
                    guard t < Self.lifetime else { continue }
                    let fade = max(0, 1 - max(0, t - 1.6) / 0.8)
                    for p in burst.pieces {
                        // Thrown up from the bottom centre, slowed by air, pulled down by gravity.
                        let drag = exp(-1.6 * t)
                        let x = size.width / 2 + p.velocity.dx * (1 - drag) / 1.6 + sin(t * 6 + p.wobble) * 8
                        let y = size.height + 20 + p.velocity.dy * (1 - drag) / 1.6 + 900 * t * t / 2
                        var piece = context
                        piece.opacity = fade
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .degrees(p.spin * t))
                        piece.scaleBy(x: 1, y: abs(cos(t * 5 + p.wobble)) * 0.8 + 0.2)
                        let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                        piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: trigger) { old, new in
            guard new > old, !reduceMotion else { return }
            fire()
        }
    }

    private func fire() {
        let pieces = (0..<110).map { _ -> Piece in
            let angle = Double.random(in: -.pi * 0.85 ... -.pi * 0.15)
            let speed = Double.random(in: 900...1700)
            return Piece(
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                spin: .random(in: -720...720),
                color: Self.colors.randomElement()!,
                size: CGSize(width: .random(in: 7...11), height: .random(in: 4...6)),
                wobble: .random(in: 0...(2 * .pi))
            )
        }
        bursts.append(Burst(pieces: pieces))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime + 0.1) {
            bursts.removeAll { Date().timeIntervalSince($0.start) >= Self.lifetime }
        }
    }
}
