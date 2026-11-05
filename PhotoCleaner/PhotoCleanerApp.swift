import SwiftData
import SwiftUI

@main
struct PhotoCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: AssetIndexEntry.self)
    }
}
