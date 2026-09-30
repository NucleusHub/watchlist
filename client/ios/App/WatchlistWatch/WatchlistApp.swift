import SwiftUI

@main
struct WatchlistApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.brand)
        }
    }
}

extension Color {
    static let brand = Color(red: 0.388, green: 0.4, blue: 0.945) // indigo-500, as on the phone
    static let favorite = Color(red: 0.957, green: 0.247, blue: 0.369)
}
