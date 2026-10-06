import NucleusUI
import SwiftUI

/// MovieDNA's double helix. SF Symbols has no DNA, so it's drawn; colour it with `foregroundStyle`.
struct DNAGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                HelixRungs().stroke(style: StrokeStyle(lineWidth: side * 0.07, lineCap: .round))
                HelixStrands().stroke(style: StrokeStyle(lineWidth: side * 0.09, lineCap: .round, lineJoin: .round))
            }
            .frame(width: side * 0.46, height: side * 0.92)
            .rotationEffect(.degrees(40))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The two backbones, one full turn top to bottom.
private struct HelixStrands: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for phase in [0, Double.pi] {
            for step in 0...40 {
                let t = Double(step) / 40
                let point = Helix.point(t, phase: phase, in: rect)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }
}

/// The base pairs between the strands, skipping where they cross.
private struct HelixRungs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for t in [0.12, 0.25, 0.38, 0.62, 0.75, 0.88] {
            path.move(to: Helix.point(t, phase: 0, in: rect))
            path.addLine(to: Helix.point(t, phase: .pi, in: rect))
        }
        return path
    }
}

private enum Helix {
    static func point(_ t: Double, phase: Double, in rect: CGRect) -> CGPoint {
        let x = rect.midX + rect.width / 2 * sin(t * 2 * .pi + phase)
        return CGPoint(x: x, y: rect.minY + rect.height * t)
    }
}

/// `IconTile` with the DNA glyph, for MovieDNA rows and toggles.
struct DNATile: View {
    var tint: NucleusTint = .rose
    var size: CGFloat = 30

    var body: some View {
        DNAGlyph()
            .foregroundStyle(.white)
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(tint.gradient))
            .shadow(color: tint.color.opacity(0.35), radius: 4, y: 2)
    }
}
