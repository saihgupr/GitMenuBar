//
//  StatusBarController.swift
//  GitMenuBar
//

import SwiftUI
import AppKit

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    let gitManager = GitManager()
    let loginItemManager = LoginItemManager()
    let githubAuthManager: GitHubAuthManager

    init(githubAuthManager: GitHubAuthManager) {
        self.githubAuthManager = githubAuthManager
        
        // Wire up token provider for git push operations
        gitManager.tokenProvider = { [weak githubAuthManager] in
            githubAuthManager?.getStoredToken()
        }
        
        // Wire up GitHub API client for checking repo existence
        gitManager.githubAPIClient = GitHubAPIClient(authManager: githubAuthManager)
        
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)

        if let button = statusItem?.button {
            // Use the custom menu bar icon
            if let image = NSImage(named: "MenuBarIcon") {
                let newSize = NSSize(width: 18, height: 18) // Standard menu bar icon size
                image.size = newSize
                image.isTemplate = true // Allow it to adapt to light/dark mode
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "GitBar")
                button.image?.isTemplate = true
            }

            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    func togglePopoverBehavior() {
        if popover?.behavior == .transient {
            popover?.behavior = .applicationDefined
        } else {
            popover?.behavior = .transient
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient

        let rootView = MainMenuView(
            closePopover: {
                self.popover?.perform(#selector(NSPopover.close), with: nil, afterDelay: 0)
            },
            togglePopoverBehavior: {
                self.togglePopoverBehavior()
            }
        )
            .environmentObject(gitManager)
            .environmentObject(loginItemManager)
            .environmentObject(githubAuthManager)

        popover?.contentViewController = PopoverHostingController(rootView: rootView)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let popover = popover {
            if popover.isShown {
                popover.perform(#selector(NSPopover.close), with: nil, afterDelay: 0)
            } else {
                // Check if current repo path is set and is a git repo
                let currentPath = UserDefaults.standard.string(forKey: "gitRepoPath") ?? ""
                let isGitRepo = !currentPath.isEmpty && gitManager.isGitRepository(at: currentPath)
                
                if isGitRepo && githubAuthManager.isAuthenticated {
                    // Check if remote exists on GitHub
                    gitManager.remoteRepositoryExists(at: currentPath) { [weak self] exists in
                        guard let self = self else { return }
                        
                        // If remote doesn't exist, show create repo view
                        if !exists {
                            self.showCreateRepoView(path: currentPath)
                        } else {
                            // Normal flow - show main view
                            self.showMainView()
                        }
                    }
                } else {
                    // Not a git repo or not authenticated - show main view
                    showMainView()
                }
            }
        }
    }
    
    private func showCreateRepoView(path: String) {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        popover.contentViewController = nil
        let rootView = MainMenuView(
            closePopover: {
                self.popover?.perform(#selector(NSPopover.close), with: nil, afterDelay: 0)
            },
            togglePopoverBehavior: {
                self.togglePopoverBehavior()
            },
            initialCreateRepoPath: path
        )
            .environmentObject(self.gitManager)
            .environmentObject(self.loginItemManager)
            .environmentObject(self.githubAuthManager)
        
        let hostingController = PopoverHostingController(rootView: rootView)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 400, height: 500)
        
        NSApp.activate(ignoringOtherApps: true)
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    private func showMainView() {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        // OPTIMIZED: Only wait for uncommittedFiles (the essential data)
        // This is much faster than waiting for all git operations
        self.gitManager.updateUncommittedFiles { [weak self] in
            guard let self = self else { return }
            
            // Always create a fresh view when opening to ensure we start at main page
            popover.contentViewController = nil
            let rootView = MainMenuView(
                closePopover: {
                    self.popover?.perform(#selector(NSPopover.close), with: nil, afterDelay: 0)
                },
                togglePopoverBehavior: {
                    self.togglePopoverBehavior()
                }
            )
                .environmentObject(self.gitManager)
                .environmentObject(self.loginItemManager)
                .environmentObject(self.githubAuthManager)
            
            let hostingController = PopoverHostingController(rootView: rootView)
            popover.contentViewController = hostingController
            
            // Set initial size
            popover.contentSize = NSSize(width: 400, height: 500)

            // Ensure app is active and show popover
            NSApp.activate(ignoringOtherApps: true)
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            // Load everything else in background AFTER popover is shown
            self.gitManager.refresh()
        }
    }
    
    /// Opens the popover programmatically (used when app is launched with a folder path)
    func openPopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        // If already shown, just activate the app
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Same logic as togglePopover for opening
        self.gitManager.updateUncommittedFiles { [weak self] in
            guard let self = self else { return }
            
            popover.contentViewController = nil
            let rootView = MainMenuView(
                closePopover: {
                    self.popover?.perform(#selector(NSPopover.close), with: nil, afterDelay: 0)
                },
                togglePopoverBehavior: {
                    self.togglePopoverBehavior()
                }
            )
                .environmentObject(self.gitManager)
                .environmentObject(self.loginItemManager)
                .environmentObject(self.githubAuthManager)
            
            let hostingController = PopoverHostingController(rootView: rootView)
            popover.contentViewController = hostingController
            popover.contentSize = NSSize(width: 400, height: 500)
            
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            self.gitManager.refresh()
        }
    }
    
    /// Opens the popover directly showing the create repo view (used when opening a non-git folder)
    func openPopoverWithCreateRepo(path: String) {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        // If already shown, close it first
        if popover.isShown {
            popover.close()
        }
        
        popover.contentViewController = nil
        let rootView = MainMenuView(
            closePopover: {
                self.popover?.perform(#selector(NSPopover.close), with: nil, afterDelay: 0)
            },
            togglePopoverBehavior: {
                self.togglePopoverBehavior()
            },
            initialCreateRepoPath: path
        )
            .environmentObject(self.gitManager)
            .environmentObject(self.loginItemManager)
            .environmentObject(self.githubAuthManager)
        
        let hostingController = PopoverHostingController(rootView: rootView)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 400, height: 500)
        
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

class PopoverHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.window?.setContentSize(self.view.fittingSize)
    }
}
