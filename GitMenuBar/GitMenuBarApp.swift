//
//  GitMenuBarApp.swift
//  GitMenuBar
//


import SwiftUI
import AppKit

@main
struct GitMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Remove default WindowGroup since we're a menu bar app
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var githubAuthManager: GitHubAuthManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the dock icon immediately
        NSApp.setActivationPolicy(.accessory)

        // Reset user defaults to ensure main page shows
        UserDefaults.standard.set(false, forKey: "showSettings")
        
        // Create GitHub auth manager
        githubAuthManager = GitHubAuthManager()

        // Create and show status bar controller - keep strong reference
        statusBarController = StatusBarController(githubAuthManager: githubAuthManager!)

        // Check login item status after controller is created
        statusBarController?.loginItemManager.checkLoginItemStatus()
        
        // Register for URL events (OAuth callback)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen the app if clicked while hidden
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        // When app becomes inactive, reset to main view
        UserDefaults.standard.set(false, forKey: "showSettings")
    }
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        // Handle OAuth callback
        if url.scheme == "gitmenubar" && url.host == "oauth" {
            githubAuthManager?.handleCallback(url: url)
        }
    }
}

