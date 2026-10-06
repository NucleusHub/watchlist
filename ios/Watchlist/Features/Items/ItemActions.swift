import NucleusUI
import SwiftUI

/// The long-press menu for a title, the same actions in every list.
struct ItemMenu: View {
    let item: Item
    var collectionID: String? = nil
    let onDelete: () -> Void
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(Preferences.self) private var preferences
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !item.isCompleted {
            Button { Haptics.success(); store.markWatched(item.id) } label: { Label("Mark as watched", systemImage: "checkmark.circle") }
        }
        Button { Haptics.tap(); store.toggleFavorite(item.id) } label: {
            Label(item.favorite ? "Remove from favorites" : "Add to favorites", systemImage: item.favorite ? "heart.slash" : "heart")
        }
        Button { navigator.present(.editItem(item.id)) } label: { Label("Edit", systemImage: "pencil") }
        Button { navigator.present(.manageCollections(item.id)) } label: { Label("Collections", systemImage: "folder") }
        if item.isShow {
            Button { navigator.present(.seasons(item.id)) } label: { Label("Track episodes", systemImage: "list.bullet") }
        }
        Menu {
            ForEach(WatchStatus.allCases, id: \.self) { status in
                Button { store.updateItem(item.id) { $0.status = status } } label: {
                    if item.status == status { Label(status.title, systemImage: "checkmark") } else { Text(status.title) }
                }
            }
        } label: { Label("Status", systemImage: "circle.dashed") }
        if let url = OpenLinks.url(for: item, settings: store.settings) {
            Button { preferences.inAppBrowser ? navigator.browse(url, item: item) : openURL(url) } label: { Label("Open", systemImage: "arrow.up.right.square") }
        }
        if let collectionID {
            Button { store.updateItem(item.id) { $0.collectionIds.removeAll { $0 == collectionID } } } label: {
                Label("Remove from this collection", systemImage: "folder.badge.minus")
            }
        }
        Divider()
        Button(role: .destructive, action: onDelete) { DestructiveLabel("Delete", systemImage: "trash") }
    }
}

/// "Remove Dune?" anchored to the row it came from.
struct DeleteItemDialog: ViewModifier {
    let item: Item
    @Binding var isPresented: Bool
    @Environment(WatchlistStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog(Text("Delete “\(item.title)”?"), isPresented: $isPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Haptics.warning()
                withAnimation(NucleusMotion.quick) { store.deleteItem(item.id) }
            }
        } message: {
            Text("It's removed from your watchlist and every collection.")
        }
    }
}

/// "Reset progress" with the options that fit the title: a movie's time, or a show's episode, season or everything.
struct ResetProgressDialog: ViewModifier {
    let item: Item
    @Binding var isPresented: Bool
    @Environment(WatchlistStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog(Text("Reset progress"), isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(item.resetActions) { action in
                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                    Haptics.warning()
                    withAnimation(NucleusMotion.quick) { store.resetProgress(item.id, ProgressReset(rawValue: action.id) ?? .current) }
                }
            }
        } message: {
            Text(item.isShow ? "Resetting a season or the whole show also clears the episodes you've marked watched."
                             : "Clears the saved time and takes it out of Jump back in.")
        }
    }
}

/// Round "mark watched" button: empty ring when planned, clock while watching, green check when done.
struct WatchedButton: View {
    let item: Item
    var size: CGFloat = 30
    @Environment(WatchlistStore.self) private var store

    var body: some View {
        Button {
            guard !item.isCompleted else { return }
            Haptics.success()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { store.markWatched(item.id) }
        } label: {
            ZStack {
                if item.isCompleted {
                    Circle().fill(WatchStatus.completed.color)
                    Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
                } else if item.status == .watching {
                    Circle().fill(WatchStatus.watching.color.opacity(0.9))
                    Image(systemName: "clock").font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Circle().fill(.black.opacity(0.35))
                    Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.6)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(NucleusPressStyle(scale: 0.85))
        .accessibilityLabel(item.isCompleted ? "Watched" : "Mark as watched")
    }
}

/// Boosts the title in MovieDNA each time it's pressed. Unlike a favorite it isn't a state you switch off: it fades.
struct InterestedButton: View {
    let item: Item
    var size: CGFloat = 52
    @Environment(WatchlistStore.self) private var store

    var body: some View {
        let count = store.interestCount(item)
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { store.markInterested(item) }
        } label: {
            Image(systemName: count > 0 ? "flame.fill" : "flame")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(count > 0 ? Color(hex: 0xF97316) : Nucleus.glyph)
                .frame(width: size, height: size)
                .background(Circle().fill(Nucleus.well))
                .symbolEffect(.bounce, value: count)
                .contentShape(Circle())
        }
        .buttonStyle(NucleusPressStyle(scale: 0.85))
        .accessibilityLabel("Interested")
        .accessibilityHint("Boosts this title and its genres in your MovieDNA. Press again to boost more.")
    }
}

struct FavoriteButton: View {
    let item: Item
    var size: CGFloat = 30
    var onPoster = true
    @Environment(WatchlistStore.self) private var store

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { store.toggleFavorite(item.id) }
        } label: {
            Image(systemName: item.favorite ? "heart.fill" : "heart")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(item.favorite ? Color(hex: 0xF43F5E) : (onPoster ? .white : Nucleus.glyph))
                .frame(width: size, height: size)
                .background(Circle().fill(onPoster ? AnyShapeStyle(.black.opacity(0.35)) : AnyShapeStyle(Nucleus.well)))
                .symbolEffect(.bounce, value: item.favorite)
                .contentShape(Circle())
        }
        .buttonStyle(NucleusPressStyle(scale: 0.85))
        .accessibilityLabel(item.favorite ? "Remove from favorites" : "Add to favorites")
    }
}
