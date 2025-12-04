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
                // Refresh git data before creating view and wait for completion
                self.gitManager.refresh { [weak self] in
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
                    
                    if let button = self.statusItem?.button {
                        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    }
                }
            }
        }
    }
}

class PopoverHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.window?.setContentSize(self.view.fittingSize)
    }
}
