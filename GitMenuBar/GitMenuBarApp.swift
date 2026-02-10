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

        // Check for updates on launch
        UpdateChecker.shared.checkForUpdatesOnLaunch()
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
    
    // MARK: - Handle file/folder URLs opened via "open -a GitMenuBar /path/to/folder"
    
    func application(_ application: NSApplication, open urls: [URL]) {
        // Handle folder paths passed via "open -a GitMenuBar /path/to/folder"
        guard let folderUrl = urls.first else {
            return
        }
        
        let path = folderUrl.path
        
        // Verify the path exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("GitMenuBar: Path is not a directory: \(path)")
            return
        }
        
        // Check if this is a git repository
        let gitPath = (path as NSString).appendingPathComponent(".git")
        let isGitRepo = FileManager.default.fileExists(atPath: gitPath)
        
        if isGitRepo && githubAuthManager?.isAuthenticated == true {
            // Check if remote repo actually exists on GitHub
            statusBarController?.gitManager.remoteRepositoryExists(at: path) { [weak self] exists in
                guard let self = self else { return }
                
                UserDefaults.standard.set(path, forKey: "gitRepoPath")
                self.addToRecents(path)
                
                if exists {
                    // Remote exists - open normally
                    self.statusBarController?.gitManager.refresh {
                        DispatchQueue.main.async {
                            self.statusBarController?.openPopover()
                        }
                    }
                } else {
                    // Remote doesn't exist (either no remote or 404) - show create repo UI
                    DispatchQueue.main.async {
                        self.statusBarController?.openPopoverWithCreateRepo(path: path)
                    }
                }
            }
        } else if isGitRepo {
            // Git repo but not authenticated - just open normally
            UserDefaults.standard.set(path, forKey: "gitRepoPath")
            addToRecents(path)
            
            statusBarController?.gitManager.refresh {
                DispatchQueue.main.async {
                    self.statusBarController?.openPopover()
                }
            }
        } else {
            // Not a git repo at all - show create repo window if GitHub is connected
            if githubAuthManager?.isAuthenticated == true {
                UserDefaults.standard.set(path, forKey: "gitRepoPath")
                addToRecents(path)
                
                DispatchQueue.main.async {
                    self.statusBarController?.openPopoverWithCreateRepo(path: path)
                }
            } else {
                // Not connected to GitHub - just open normally
                UserDefaults.standard.set(path, forKey: "gitRepoPath")
                addToRecents(path)
                
                statusBarController?.gitManager.refresh {
                    DispatchQueue.main.async {
                        self.statusBarController?.openPopover()
                    }
                }
            }
        }
    }
    
    private func addToRecents(_ path: String) {
        // Decode existing recents
        let data = UserDefaults.standard.data(forKey: "recentRepoPaths") ?? Data()
        var current = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        
        // Remove if exists to move to top
        current.removeAll { $0 == path }
        // Add to top
        current.insert(path, at: 0)
        // Keep only last 5
        if current.count > 5 {
            current = Array(current.prefix(5))
        }
        
        // Save
        if let encoded = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(encoded, forKey: "recentRepoPaths")
        }
    }
}
