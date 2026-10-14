//
//  AfterWorkApp.swift
//  AfterWork
//
//  Created by Yernar Nurbank on 13.10.2026.
//

import SwiftUI

@main
struct AfterWorkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
