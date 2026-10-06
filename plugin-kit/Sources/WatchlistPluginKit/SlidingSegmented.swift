#if canImport(UIKit)
import NucleusUI
import SwiftUI
import UIKit

/// NucleusUI's segmented pills, but with the highlight following a `PagedCarousel` while it's dragged,
/// so the pill slides along with the pages instead of jumping when they settle.
public struct SlidingSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, title: LocalizedStringKey)]
    let fill: Bool
    let progress: CarouselProgress?
    @State private var frames: [Int: CGRect] = [:]

    public init(selection: Binding<Value>, items: [(value: Value, title: LocalizedStringKey)], fill: Bool = false, progress: CarouselProgress? = nil) {
        _selection = selection
        self.items = items
        self.fill = fill
        self.progress = progress
    }

    public var body: some View {
        let selected = items.firstIndex { $0.value == selection } ?? 0
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    guard item.value != selection else { return }
                    Haptics.selection()
                    selection = item.value
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(index == selected ? Nucleus.primaryText : Nucleus.secondaryText)
                        .padding(.horizontal, fill ? 6 : 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .contentShape(Rectangle())
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: SegmentFrames.self, value: [index: geo.frame(in: .named("segments"))])
                        })
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selected ? .isSelected : [])
            }
        }
        // Only the highlight follows the finger; the labels and the header around them don't redraw mid-drag.
        .background(alignment: .topLeading) {
            SegmentHighlight(frames: frames, count: items.count, selected: selected, progress: progress)
        }
        .coordinateSpace(.named("segments"))
        .onPreferenceChange(SegmentFrames.self) { if frames != $0 { frames = $0 } }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: NucleusRadius.segmentTrack, style: .continuous)
            .fill(Self.dynamic(light: .black.withAlphaComponent(0.04), dark: .white.withAlphaComponent(0.05))))
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The pill: between two segments while dragging it takes the in-between place and width.
private struct SegmentHighlight: View {
    let frames: [Int: CGRect]
    let count: Int
    let selected: Int
    let progress: CarouselProgress?

    var body: some View {
        let position = progress?.isDragging == true ? progress!.position : CGFloat(selected)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        if count > 0, let a = frames[min(max(lower, 0), count - 1)], let b = frames[min(max(upper, 0), count - 1)] {
            let t = position - CGFloat(lower)
            RoundedRectangle(cornerRadius: NucleusRadius.segmentPill, style: .continuous)
                .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.15) : .white }))
                .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                .frame(width: a.width + (b.width - a.width) * t, height: a.height)
                .offset(x: a.minX + (b.minX - a.minX) * t, y: a.minY)
                .animation(NucleusMotion.quick, value: progress?.isDragging == true ? -1 : selected)
        }
    }
}

private struct SegmentFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}
#endif
