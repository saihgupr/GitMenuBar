//
//  MainMenuView.swift
//  GitMenuBar
//

//

import SwiftUI
import AppKit

struct CreateRepoPath: Identifiable {
    let id = UUID()
    let path: String
}

struct MainMenuView: View {
    @State private var commentText = ""
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var createRepoPath: CreateRepoPath? = nil
    @FocusState private var isCommentFieldFocused: Bool
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    @AppStorage("recentRepoPaths") private var recentRepoPathsData: Data = Data()
    


    
    private var recentPaths: [String] {
        guard let decoded = try? JSONDecoder().decode([String].self, from: recentRepoPathsData) else {
            return []
        }
        return decoded
    }

    let closePopover: () -> Void
    let togglePopoverBehavior: () -> Void

    init(closePopover: @escaping () -> Void = {}, togglePopoverBehavior: @escaping () -> Void = {}) {
        self.closePopover = closePopover
        self.togglePopoverBehavior = togglePopoverBehavior
    }

    var body: some View {
        VStack(spacing: 10) {
            if showingSettings {
                settingsView
            } else if showingHistory {
                historyView
            } else {
                mainView
            }
        }
        .sheet(item: $createRepoPath) { repoPath in
            CreateRepoView(folderPath: repoPath.path)
                .environmentObject(gitManager)
                .environmentObject(githubAuthManager)
        }
        .padding(10)
        .frame(width: 400)
    }

    var mainView: some View {
        VStack(spacing: 8) {
            // Compact header
            HStack {
                HStack(spacing: 4) {
                    Text("GitMenuBar")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    if let repoPath = UserDefaults.standard.string(forKey: "gitRepoPath"),
                       !repoPath.isEmpty {
                        let projectName = URL(fileURLWithPath: repoPath).lastPathComponent
                        
                        if !gitManager.remoteUrl.isEmpty, let url = URL(string: gitManager.remoteUrl) {
                            Button(action: {
                                NSWorkspace.shared.open(url)
                            }) {
                                Text("- \(projectName)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .onHover { inside in
                                if inside {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        } else {
                            Text("- \(projectName)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    Button("History") {
                        showingHistory = true
                        gitManager.fetchCommitHistory()
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)

                    Text("|")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))

                    Button("Settings") {
                        showingSettings = true
                        UserDefaults.standard.set(true, forKey: "showSettings")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
            }

            Divider()
                .padding(.top, 4)

            // Branch status - compact
            HStack {
                Text("\(gitManager.currentBranch) ▲\(gitManager.commitCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(gitManager.commitCount > 0 ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
            }

            // Commit message field
            TextField("Commit message", text: $commentText, onCommit: submitComment)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isCommentFieldFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isCommentFieldFocused = true
                    }
                }


            // Modified files list
            if !gitManager.uncommittedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modified Files (\(gitManager.uncommittedFiles.count))")
                        .font(.system(size: 11, weight: .medium))
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(gitManager.uncommittedFiles, id: \.self) { file in
                                HStack {
                                    Image(systemName: "doc")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(file)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(gitManager.uncommittedFiles.count * 30), 200))
                    .id(gitManager.uncommittedFiles) // Force redraw when files change
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
            }

            Spacer()
                .frame(height: 3)

            // Action buttons
            HStack {
                if gitManager.commitCount > 0 || !gitManager.uncommittedFiles.isEmpty {
                    Button("Reset") {
                        resetToLastCommit()
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }

                Spacer()

                Button("Push to Remote") {
                    pushToRemote()
                }
                .disabled(gitManager.isCommitting)
                .buttonStyle(.borderless)
                .focusable(false)
            }
        }
        .padding(6)
        .animation(.spring(), value: gitManager.uncommittedFiles)
    }

    private func submitComment() {
        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !gitManager.isCommitting else { return }

        // Capitalize first letter
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let capitalizedText = trimmedText.prefix(1).uppercased() + trimmedText.dropFirst()

        gitManager.commitLocally(capitalizedText)
        commentText = ""

        // Wait for commit to complete, then close popover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            closePopover()
        }
    }

    private func pushToRemote() {
        let message = commentText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If there's a commit message, commit first then push
        if !message.isEmpty && !gitManager.isCommitting {
            let capitalizedText = message.prefix(1).uppercased() + message.dropFirst()

            // Commit the changes
            gitManager.commitLocally(capitalizedText)
            commentText = ""

            // Wait for commit to complete, then push, then close app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.gitManager.pushToRemote()
            }
        } else {
            // Just push if no commit message
            gitManager.pushToRemote()
        }

        // Close the popover, keep app running
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            closePopover()
        }
    }

    private func resetToLastCommit() {
        gitManager.resetToLastCommit()
        commentText = ""

        // Wait for reset to complete, then close popover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            closePopover()
        }
    }

    var settingsView: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button("Done") {
                    if let currentPath = UserDefaults.standard.string(forKey: "gitRepoPath"), !currentPath.isEmpty {
                        addToRecents(currentPath)
                        gitManager.refresh()
                    }
                    showingSettings = false
                    UserDefaults.standard.set(false, forKey: "showSettings")
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            .padding(.top, 4)

            Divider()
                .padding(.top, 4)

            // Settings content
            VStack(spacing: 12) {
                // Git Repository Path section
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Git Repository Path")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.top, 2)

                    TextField("Select repository directory", text: Binding(
                        get: { UserDefaults.standard.string(forKey: "gitRepoPath") ?? "" },
                        set: { newValue in
                            UserDefaults.standard.set(newValue, forKey: "gitRepoPath")
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    Button("Browse...") {
                        selectDirectory()
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }

                // Open at Login section
                HStack {
                    Button(action: {
                        loginItemManager.isEnabled.toggle()
                        loginItemManager.setLoginItem(enabled: loginItemManager.isEnabled)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: loginItemManager.isEnabled ? "checkmark.square" : "square")
                                .font(.system(size: 13))
                                .foregroundColor(loginItemManager.isEnabled ? .primary.opacity(0.7) : .secondary.opacity(0.5))
                            Text("Open at Login")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    Spacer()
                }
                .padding(.top, 4)
                
                // GitHub Connection section
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("GitHub")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.top, 4)
                    
                    if githubAuthManager.isAuthenticated {
                        HStack {
                            Text("Connected as @\(githubAuthManager.username)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Disconnect") {
                                githubAuthManager.disconnect()
                            }
                            .buttonStyle(.borderless)
                            .focusable(false)
                            .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    } else {
                        Button("Connect GitHub") {
                            githubAuthManager.startOAuthFlow()
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                        .font(.system(size: 12))
                    }
                }
                .padding(.top, 4)

                if !recentPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recently Used")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        ForEach(recentPaths.filter { $0 != UserDefaults.standard.string(forKey: "gitRepoPath") }.prefix(3), id: \.self) { path in
                            Button(action: {
                                UserDefaults.standard.set(path, forKey: "gitRepoPath")
                                addToRecents(path)
                                gitManager.refresh()
                            }) {
                                HStack {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(path)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func selectDirectory() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Keep popover open while file dialog is shown
        togglePopoverBehavior()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Select Git Repository"
        panel.prompt = "Choose"
        panel.worksWhenModal = false
        
        // Make panel appear on top
        DispatchQueue.main.async {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }

        panel.begin { result in
            // Restore popover behavior
            self.togglePopoverBehavior()
            
            if result == .OK, let url = panel.url {
                let path = url.path
                
                // Check if this is a git repository
                if !gitManager.isGitRepository(at: path) {
                    // Not a git repo - offer to create one if GitHub is connected
                    if githubAuthManager.isAuthenticated {
                        // Use main thread for UI updates
                        DispatchQueue.main.async {
                            self.createRepoPath = CreateRepoPath(path: path)
                        }
                    } else {
                        // Just set the path anyway - user can manually init git
                        UserDefaults.standard.set(path, forKey: "gitRepoPath")
                        addToRecents(path)
                        gitManager.refresh()
                    }
                } else {
                    // Is a git repo - set it normally
                    UserDefaults.standard.set(path, forKey: "gitRepoPath")
                    addToRecents(path)
                    gitManager.refresh()
                }
            }
        }
    }
    
    private func addToRecents(_ path: String) {
        var current = recentPaths
        // Remove if exists to move to top
        current.removeAll { $0 == path }
        // Add to top
        current.insert(path, at: 0)
        // Keep only last 5 to ensure we have enough to show 3 others
        if current.count > 5 {
            current = Array(current.prefix(5))
        }
        
        if let encoded = try? JSONEncoder().encode(current) {
            recentRepoPathsData = encoded
        }
    }
    
    private func isCommitInFuture(_ commit: Commit) -> Bool {
        // A commit is "future" if it appears before current HEAD in the history list
        // This happens when we've reset backwards
        guard let currentIndex = gitManager.commitHistory.firstIndex(where: { $0.id == gitManager.currentHash }),
              let commitIndex = gitManager.commitHistory.firstIndex(where: { $0.id == commit.id }) else {
            return false
        }
        return commitIndex < currentIndex
    }

    var historyView: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("History")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button("Done") {
                    showingHistory = false
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            .padding(.top, 4)

            Divider()
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(gitManager.commitHistory) { commit in
                        let isFutureCommit = isCommitInFuture(commit)
                        
                        Button(action: {
                            if commit.id != gitManager.currentHash {
                                gitManager.resetToCommit(commit.id)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Text(commit.message)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundColor(isFutureCommit ? .blue : .primary)
                                    .layoutPriority(1)
                                
                                Spacer()
                                
                                if isFutureCommit {
                                    Text("Future")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                
                                HStack(spacing: 4) {
                                    Text(commit.date)
                                }
                                .font(.system(size: 10))
                                .foregroundColor(isFutureCommit ? .blue.opacity(0.7) : .secondary)
                                .lineLimit(1)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .background(commit.id == gitManager.currentHash ? Color.primary.opacity(0.05) : Color.clear)
                        .onHover { inside in
                            if inside && commit.id != gitManager.currentHash {
                                NSCursor.pointingHand.push()
                            } else if !inside {
                                NSCursor.pop()
                            }
                        }
                        
                        Divider()
                    }
                }
            }
            .frame(height: 200) // Smaller height as requested
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    MainMenuView()
}
