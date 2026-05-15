//
//  Claude_Usage_ViewerApp.swift
//  Claude Usage Viewer
//
//  Created by BJ Blaker on 5/14/26.
//

import SwiftUI
import SwiftData

@main
struct Claude_Usage_ViewerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
