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
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    @State private var showWipeConfirmation = false
    @State private var isWiping = false
    @State private var wipeError: String? = nil
    @State private var showRepoOptions = false
    @State private var showVisibilityConfirmation = false
    @State private var isTogglingVisibility = false
    @State private var toggleVisibilityError: String? = nil
    @FocusState private var isCommentFieldFocused: Bool
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    @AppStorage("recentRepoPaths") private var recentRepoPathsData: Data = Data()
    @AppStorage("showFullPathInRecents") private var showFullPathInRecents = false
    @State private var showBranchSelector = false
    @State private var selectedPushBranch: String = ""
    @State private var showSyncOptions = false
    @State private var showPullToNewBranch = false
    @State private var pullToNewBranchName = ""
    @State private var useRebase = false
    @State private var syncError: String? = nil
    @State private var branchSwitchError: String? = nil
    @State private var showCreateBranch = false
    @State private var newBranchName: String = ""
    @State private var createBranchError: String? = nil
    @State private var mergeError: String? = nil
    @State private var deleteBranchError: String? = nil
    @State private var pushError: String? = nil
    
    // Rename branch states
    @State private var showRenameBranch = false
    @State private var oldBranchName = ""
    @State private var renameBranchNewName = ""
    @State private var renameBranchError: String? = nil
    
    // Merge confirmation states
    @State private var showMergeConfirmation = false
    @State private var mergeBranchName = ""
    @State private var mergeTargetBranch = ""
    
    // Switch confirmation states
    @State private var showDirtySwitchConfirmation = false
    @State private var pendingSwitchBranch = ""
    
    // Delete confirmation states
    @State private var showBranchDeleteConfirmation = false
    @State private var branchNameToDelete = ""
    

    


    
    private var recentPaths: [String] {
        guard let decoded = try? JSONDecoder().decode([String].self, from: recentRepoPathsData) else {
            return []
        }
        return decoded
    }

    let closePopover: () -> Void
    let togglePopoverBehavior: () -> Void
    let initialCreateRepoPath: String?

    init(closePopover: @escaping () -> Void = {}, togglePopoverBehavior: @escaping () -> Void = {}, initialCreateRepoPath: String? = nil) {
        self.closePopover = closePopover
        self.togglePopoverBehavior = togglePopoverBehavior
        self.initialCreateRepoPath = initialCreateRepoPath
        if let path = initialCreateRepoPath {
            _createRepoPath = State(initialValue: CreateRepoPath(path: path))
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let repoPath = createRepoPath {
                createRepoView(folderPath: repoPath.path)
            } else if showingSettings {
                settingsView
            } else if showingHistory {
                historyView
            } else {
                mainView
            }
        }
        .alert("Delete Repository?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRepository()
            }
            .disabled(isDeleting)
        } message: {
            Text("This will permanently delete the repository from GitHub. This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
        .alert(gitManager.isPrivate ? "Make Repository Public?" : "Make Repository Private?", isPresented: $showVisibilityConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(gitManager.isPrivate ? "Make Public" : "Make Private") {
                toggleRepoVisibility()
            }
        } message: {
            Text(gitManager.isPrivate ? "Anyone on the internet will be able to see this repository." : "You will choose who can see and commit to this repository.")
        }
        .alert("Wipe Repository History?", isPresented: $showWipeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Wipe", role: .destructive) {
                wipeRepository()
            }
            .disabled(isWiping)
        } message: {
            Text("This will permanently erase all commit history and reset the repository to a single 'Initial commit'. Your current files will be preserved. This action cannot be undone.")
        }
        .alert("Wipe Failed", isPresented: .init(
            get: { wipeError != nil },
            set: { if !$0 { wipeError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(wipeError ?? "An unknown error occurred.")
        }
        .confirmationDialog("Repository Options", isPresented: $showRepoOptions) {
            Button(gitManager.isPrivate ? "Make Public" : "Make Private") {
                // Delay to allow menu to dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showVisibilityConfirmation = true
                }
            }
            Button("Delete Repository", role: .destructive) {
                // Delay to allow menu to dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showDeleteConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(gitManager.isPrivate ? "This repository is currently private." : "This repository is currently public.")
        }
        .alert("Visibility Update Failed", isPresented: .init(
            get: { toggleVisibilityError != nil },
            set: { if !$0 { toggleVisibilityError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(toggleVisibilityError ?? "An unknown error occurred.")
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
                            Text("- \(projectName)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .onTapGesture {
                                    if NSEvent.modifierFlags.contains(.command) {
                                        // Cmd+click: Open folder in Finder
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repoPath)
                                    } else {
                                        // Regular click: Open GitHub URL (branch or commit specific)
                                        var finalURL = url
                                        if gitManager.isDetachedHead {
                                            // Open specific commit if in detached HEAD
                                            if let commitURL = URL(string: gitManager.remoteUrl + "/commit/" + gitManager.currentHash) {
                                                finalURL = commitURL
                                            }
                                        } else {
                                            // Open current branch
                                            if let branchURL = URL(string: gitManager.remoteUrl + "/tree/" + gitManager.currentBranch) {
                                                finalURL = branchURL
                                            }
                                        }
                                        NSWorkspace.shared.open(finalURL)
                                    }
                                }
                                .onLongPressGesture(minimumDuration: 2.0) {
                                    showRepoOptions = true
                                }
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
            .padding(.top, 4)

            Divider()
                .padding(.top, 4)

            // Branch status - compact with branch selector and remote status
            HStack(spacing: 4) {
                Button(action: { showBranchSelector.toggle() }) {
                    HStack(spacing: 0) {
                        Text("\(gitManager.currentBranch)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        
                        // Ahead indicator
                        Text(" ▲")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        Text("\(gitManager.commitCount)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 12, alignment: .leading)
                        
                        // Behind indicator
                        if gitManager.isRemoteAhead {
                            Text(" ▼")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                            Text("\(gitManager.behindCount)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                                .monospacedDigit()
                                .frame(minWidth: 12, alignment: .leading)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(gitManager.isDetachedHead ? Color.red.opacity(0.3) :
                                gitManager.isRemoteAhead ? Color.orange.opacity(0.2) : 
                                gitManager.commitCount > 0 ? Color.orange.opacity(0.2) : 
                                Color.green.opacity(0.2))
                    .clipShape(Capsule())
                    .animation(nil, value: gitManager.currentBranch)
                    .animation(nil, value: gitManager.commitCount)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .popover(isPresented: $showBranchSelector) {
                    VStack(alignment: .leading, spacing: 0) {
                        if gitManager.isDetachedHead {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("Detached HEAD State")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                
                                Text("You aren't on a branch. Edits made here might be hard to find later.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button(action: {
                                    showBranchSelector = false
                                    showCreateBranch = true
                                }) {
                                    Label("Create Branch from here...", systemImage: "plus.branch")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .tint(.accentColor)
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.05))
                            
                            Divider()
                        }
                        
                        Text("Branches")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        
                        Divider()
                            .padding(.horizontal, 10)
                        
                        // Quick Pull option when remote is ahead
                        if gitManager.isRemoteAhead {
                            Button(action: {
                                showBranchSelector = false
                                useRebase = false // Default to merge for quick pull
                                syncWithRemote()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pull \(gitManager.behindCount) commits")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("Update current branch from remote")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.1))
                            }
                            .buttonStyle(.plain)
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            
                            Divider()
                                .padding(.horizontal, 10)
                        }
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(gitManager.availableBranches, id: \.self) { branch in
                                    BranchRowView(
                                        branchName: branch,
                                        isCurrentBranch: branch == gitManager.currentBranch,
                                        currentBranchName: gitManager.currentBranch,
                                        onTap: {
                                            showBranchSelector = false
                                            if branch != gitManager.currentBranch {
                                                if !gitManager.uncommittedFiles.isEmpty {
                                                    pendingSwitchBranch = branch
                                                    showDirtySwitchConfirmation = true
                                                } else {
                                                    gitManager.switchBranch(branchName: branch) { result in
                                                        if case .failure(let error) = result {
                                                            branchSwitchError = error.localizedDescription
                                                        }
                                                    }
                                                }
                                            }
                                        },
                                        onMerge: branch != gitManager.currentBranch ? {
                                            showBranchSelector = false
                                            if gitManager.currentBranch == "main" || gitManager.currentBranch == "master" {
                                                mergeBranchName = branch
                                                mergeTargetBranch = gitManager.currentBranch
                                                showMergeConfirmation = true
                                            } else {
                                                gitManager.mergeBranch(fromBranch: branch) { result in
                                                    if case .failure(let error) = result {
                                                        mergeError = error.localizedDescription
                                                    }
                                                }
                                            }
                                        } : nil,
                                        onDelete: branch != gitManager.currentBranch ? {
                                            showBranchSelector = false
                                            branchNameToDelete = branch
                                            showBranchDeleteConfirmation = true
                                        } : nil,
                                        onRename: {
                                            showBranchSelector = false
                                            oldBranchName = branch
                                            renameBranchNewName = branch
                                            showRenameBranch = true
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 200)
                        
                        Divider()
                            .padding(.horizontal, 10)
                        
                        NewBranchButton(onTap: {
                            showBranchSelector = false
                            showCreateBranch = true
                        })
                    }
                    .frame(width: 200)
                    .padding(.bottom, 4)
                }
                
                
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



            // Modified files list - Always render container for reactive updates
            VStack(alignment: .leading, spacing: 6) {
                Text("Modified Files (\(gitManager.uncommittedFiles.count))")
                    .font(.system(size: 11, weight: .medium))
                
                if !gitManager.uncommittedFiles.isEmpty {
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
                    .frame(maxHeight: min(CGFloat(gitManager.uncommittedFiles.count * 26), 200))
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading) // Ensure left alignment even when empty
            .id(gitManager.uncommittedFiles.count) // Force redraw when count changes



            Spacer()
                .frame(height: 3)

            // Action buttons
            HStack {
                if gitManager.isRemoteAhead {
                    Button("Sync") {
                        showSyncOptions = true
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                
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
                .keyboardShortcut("p", modifiers: .command) // Cmd+P
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .onExitCommand {
            closePopover()
        }
        .background(
            // Hidden button to handle Cmd+Enter globally (bypassing text field focus)
            Button("Commit Hidden") {
                pushToRemote()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
        )
        .alert("Push Failed", isPresented: .init(
            get: { pushError != nil },
            set: { if !$0 { pushError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pushError ?? "An unknown error occurred.")
        }
        .alert("Sync Failed", isPresented: .init(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncError ?? "An unknown error occurred.")
        }
        .alert("Branch Switch Failed", isPresented: .init(
            get: { branchSwitchError != nil },
            set: { if !$0 { branchSwitchError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(branchSwitchError ?? "An unknown error occurred.")
        }
        .alert("Merge Failed", isPresented: .init(
            get: { mergeError != nil },
            set: { if !$0 { mergeError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mergeError ?? "An unknown error occurred.")
        }
        .alert("Delete Failed", isPresented: .init(
            get: { deleteBranchError != nil },
            set: { if !$0 { deleteBranchError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteBranchError ?? "An unknown error occurred.")
        }
        .alert("Rename Failed", isPresented: .init(
            get: { renameBranchError != nil },
            set: { if !$0 { renameBranchError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(renameBranchError ?? "An unknown error occurred.")
        }
        .alert("Merge into \(mergeTargetBranch)?", isPresented: $showMergeConfirmation) {
            Button("Merge") {
                gitManager.mergeBranch(fromBranch: mergeBranchName) { result in
                    if case .failure(let error) = result {
                        mergeError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                mergeBranchName = ""
                mergeTargetBranch = ""
            }
        } message: {
            Text("This will bring all changes from '\(mergeBranchName)' into your current branch '\(mergeTargetBranch)'.")
        }
        .alert("Uncommitted Changes", isPresented: $showDirtySwitchConfirmation) {
            Button("Switch & Carry Over") {
                gitManager.switchBranch(branchName: pendingSwitchBranch) { result in
                    if case .failure(let error) = result {
                        branchSwitchError = error.localizedDescription
                    }
                }
                pendingSwitchBranch = ""
            }
            Button("Cancel", role: .cancel) {
                pendingSwitchBranch = ""
            }
        } message: {
            Text("You have uncommitted changes. They will follow you to '\(pendingSwitchBranch)'.")
        }
        .alert("Delete '\(branchNameToDelete)'?", isPresented: $showBranchDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                gitManager.deleteBranch(branchName: branchNameToDelete) { result in
                    if case .failure(let error) = result {
                        deleteBranchError = error.localizedDescription
                    }
                }
                branchNameToDelete = ""
            }
            Button("Cancel", role: .cancel) {
                branchNameToDelete = ""
            }
        } message: {
            Text((branchNameToDelete == "main" || branchNameToDelete == "master" || branchNameToDelete == "develop") ?
                 "WARNING: '\(branchNameToDelete)' is a primary branch. Deleting it may cause serious issues." :
                 "Are you sure you want to delete this branch? This action cannot be undone.")
        }
    
        .sheet(isPresented: $showRenameBranch) {
            VStack(spacing: 16) {
                Text("Rename Branch")
                    .font(.system(size: 14, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("New name for '\(oldBranchName)':")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("new-branch-name", text: $renameBranchNewName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            renameBranch()
                        }
                }
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        showRenameBranch = false
                        renameBranchNewName = ""
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Spacer()
                    
                    Button("Rename") {
                        renameBranch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameBranchNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameBranchNewName == oldBranchName)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(isPresented: $showSyncOptions) {
            VStack(spacing: 16) {
                Text("Sync with Remote")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        useRebase = false
                        syncWithRemote()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Merge")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Safe: Creates a merge commit")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.borderless)
                    
                    .buttonStyle(.borderless)
                    
                    Button(action: {
                        useRebase = true
                        syncWithRemote()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rebase")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Clean: Replays your commits on top")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: {
                        showSyncOptions = false
                        pullToNewBranchName = "\(gitManager.currentBranch)-remote"
                        showPullToNewBranch = true
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pull to New Branch")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Safe: Creates a fresh branch from remote")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.borderless)
                }
                
                Button("Cancel") {
                    showSyncOptions = false
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            .padding()
            .frame(width: 320)
        }
        .sheet(isPresented: $showCreateBranch) {
            VStack(spacing: 16) {
                Text("Create New Branch")
                    .font(.system(size: 14, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Branch Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("feature/new-feature", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            if !newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                createNewBranch()
                            }
                        }
                    
                    if let error = createBranchError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    
                    Text("Will branch from: \(gitManager.currentBranch)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Button("Cancel") {
                        showCreateBranch = false
                        newBranchName = ""
                        createBranchError = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Create") {
                        createNewBranch()
                    }
                    .buttonStyle(.borderless)
                    .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .sheet(isPresented: $showPullToNewBranch) {
            VStack(spacing: 16) {
                Text("Pull to New Branch")
                    .font(.system(size: 14, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch name:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("branch-name", text: $pullToNewBranchName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            pullToNewBranch()
                        }
                }
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        showPullToNewBranch = false
                        pullToNewBranchName = ""
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Spacer()
                    
                    Button("Pull") {
                        pullToNewBranch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pullToNewBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 320)
        }
    }

    private func submitComment() {
        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !gitManager.isCommitting else { return }

        // Capitalize first letter
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let capitalizedText = trimmedText.prefix(1).uppercased() + trimmedText.dropFirst()

        commentText = ""
        
        // Wait for commit to complete, then close popover
        gitManager.commitLocally(capitalizedText) {
            self.closePopover()
        }
    }

    private func pushToRemote() {
        let message = commentText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If there's a commit message, commit first then push
        if !message.isEmpty && !gitManager.isCommitting {
            let capitalizedText = message.prefix(1).uppercased() + message.dropFirst()

            // Commit the changes AND THEN push (skip UI updates since we're closing on success)
            gitManager.commitLocally(capitalizedText, skipUIUpdates: true) {
                // Once commit is done, push to remote
                self.gitManager.pushToRemote { result in
                    switch result {
                    case .success:
                        self.closePopover()
                    case .failure(let error):
                        self.pushError = error.localizedDescription
                    }
                }
            }
            commentText = ""
        } else {
            // Just push if no commit message
            gitManager.pushToRemote { result in
                switch result {
                case .success:
                    self.closePopover()
                case .failure(let error):
                    self.pushError = error.localizedDescription
                }
            }
        }
    }
    
    private func syncWithRemote() {
        showSyncOptions = false
        gitManager.pullFromRemote(rebase: useRebase) { result in
            switch result {
            case .success:
                // Refresh after successful pull
                self.gitManager.refresh {
                    self.closePopover()
                }
            case .failure(let error):
                self.syncError = error.localizedDescription
            }
        }
    }
    
    private func createNewBranch() {
        createBranchError = nil
        gitManager.createBranch(branchName: newBranchName) { result in
            switch result {
            case .success:
                showCreateBranch = false
                newBranchName = ""
            case .failure(let error):
                createBranchError = error.localizedDescription
            }
        }
    }

    private func renameBranch() {
        renameBranchError = nil
        gitManager.renameBranch(oldName: oldBranchName, newName: renameBranchNewName) { result in
            switch result {
            case .success:
                showRenameBranch = false
                renameBranchNewName = ""
                oldBranchName = ""
            case .failure(let error):
                renameBranchError = error.localizedDescription
            }
        }
    }

    private func pullToNewBranch() {
        let name = pullToNewBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        gitManager.pullToNewBranch(newBranchName: name) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showPullToNewBranch = false
                    pullToNewBranchName = ""
                case .failure(let error):
                    syncError = error.localizedDescription
                }
            }
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
    
    private func deleteRepository() {
        // Parse owner and repo name from remote URL
        // Supports formats like:
        // https://github.com/owner/repo.git
        // https://github.com/owner/repo
        // git@github.com:owner/repo.git
        
        let remoteUrl = gitManager.remoteUrl
        var owner: String?
        var repoName: String?
        
        if remoteUrl.contains("github.com") {
            // HTTPS format: https://github.com/owner/repo.git
            if let url = URL(string: remoteUrl) {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 2 {
                    owner = pathComponents[0]
                    repoName = pathComponents[1].replacingOccurrences(of: ".git", with: "")
                }
            }
            // SSH format: git@github.com:owner/repo.git
            else if remoteUrl.hasPrefix("git@github.com:") {
                let path = remoteUrl.replacingOccurrences(of: "git@github.com:", with: "")
                let parts = path.split(separator: "/")
                if parts.count >= 2 {
                    owner = String(parts[0])
                    repoName = String(parts[1]).replacingOccurrences(of: ".git", with: "")
                }
            }
        }
        
        guard let owner = owner, let repoName = repoName else {
            deleteError = "Could not parse repository owner and name from remote URL"
            return
        }
        
        isDeleting = true
        
        Task {
            do {
                let apiClient = GitHubAPIClient(authManager: githubAuthManager)
                try await apiClient.deleteRepository(owner: owner, name: repoName)
                
                await MainActor.run {
                    isDeleting = false
                    // Clear the remote URL since repo is deleted
                    gitManager.remoteUrl = ""
                    closePopover()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }
    
    private func toggleRepoVisibility() {
        let remoteUrl = gitManager.remoteUrl
        var owner: String?
        var repoName: String?
        
        if remoteUrl.contains("github.com") {
            // HTTPS format: https://github.com/owner/repo.git
            if let url = URL(string: remoteUrl) {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 2 {
                    owner = pathComponents[0]
                    repoName = pathComponents[1].replacingOccurrences(of: ".git", with: "")
                }
            }
            // SSH format: git@github.com:owner/repo.git
            else if remoteUrl.hasPrefix("git@github.com:") {
                let path = remoteUrl.replacingOccurrences(of: "git@github.com:", with: "")
                let parts = path.split(separator: "/")
                if parts.count >= 2 {
                    owner = String(parts[0])
                    repoName = String(parts[1]).replacingOccurrences(of: ".git", with: "")
                }
            }
        }
        
        guard let owner = owner, let repoName = repoName else {
            toggleVisibilityError = "Could not parse repository owner and name from remote URL"
            return
        }
        
        isTogglingVisibility = true
        let newStatus = !gitManager.isPrivate
        
        Task {
            do {
                let apiClient = GitHubAPIClient(authManager: githubAuthManager)
                _ = try await apiClient.updateRepositoryVisibility(owner: owner, name: repoName, isPrivate: newStatus)
                
                await MainActor.run {
                    isTogglingVisibility = false
                    gitManager.checkRepoVisibility()
                }
            } catch {
                await MainActor.run {
                    isTogglingVisibility = false
                    toggleVisibilityError = error.localizedDescription
                }
            }
        }
    }
    
    private func wipeRepository() {
        isWiping = true
        
        gitManager.wipeRepository { result in
            DispatchQueue.main.async {
                isWiping = false
                switch result {
                case .success:
                    showingSettings = false
                    UserDefaults.standard.set(false, forKey: "showSettings")
                case .failure(let error):
                    wipeError = error.localizedDescription
                }
            }
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
                        get: { ((UserDefaults.standard.string(forKey: "gitRepoPath") ?? "") as NSString).abbreviatingWithTildeInPath },
                        set: { newValue in
                            UserDefaults.standard.set((newValue as NSString).expandingTildeInPath, forKey: "gitRepoPath")
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
                    } else if githubAuthManager.isAuthenticating {
                        // Device Flow: Show user code
                        VStack(spacing: 12) {
                            if !githubAuthManager.userCode.isEmpty {
                                VStack(spacing: 8) {
                                    // Code display - prominent and centered
                                    VStack(spacing: 4) {
                                        Text(githubAuthManager.userCode)
                                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .kerning(2)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                            Text("Copied to clipboard")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    // Status
                                    Text("Enter this code on GitHub")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    // Cancel button
                                    Button("Cancel") {
                                        githubAuthManager.cancelAuthentication()
                                    }
                                    .buttonStyle(.borderless)
                                    .focusable(false)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Connecting...")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Not connected")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Connect") {
                                    // Keep popover open while browser is in focus
                                    togglePopoverBehavior()
                                    githubAuthManager.startDeviceFlow()
                                }
                                .buttonStyle(.borderless)
                                .focusable(false)
                                .font(.system(size: 11))
                            }
                            if !githubAuthManager.authError.isEmpty {
                                Text(githubAuthManager.authError)
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                .padding(.top, 4)
                .onChange(of: githubAuthManager.isAuthenticating) { _, isAuthenticating in
                    // When authentication ends (success or cancel), revert popover behavior
                    if !isAuthenticating {
                        togglePopoverBehavior()
                    }
                }


                if !recentPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Recently Used")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFullPathInRecents.toggle()
                            }
                        }
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .help("Click to toggle between full path and project name")
                        
                        ForEach(recentPaths.filter { $0 != UserDefaults.standard.string(forKey: "gitRepoPath") }.prefix(5), id: \.self) { path in
                            let abbreviatedPath = (path as NSString).abbreviatingWithTildeInPath
                            let displayName = showFullPathInRecents ? abbreviatedPath : URL(fileURLWithPath: path).lastPathComponent
                            RecentPathRowView(
                                displayText: displayName,
                                fullPath: abbreviatedPath,
                                onTap: {
                                    // Check if this is a git repository
                                    if !gitManager.isGitRepository(at: path) {
                                        // Not a git repo - offer to create one if GitHub is connected
                                        if githubAuthManager.isAuthenticated {
                                            createRepoPath = CreateRepoPath(path: path)
                                        } else {
                                            // Just set the path anyway - user can manually init git
                                            UserDefaults.standard.set(path, forKey: "gitRepoPath")
                                            addToRecents(path)
                                            gitManager.refresh {
                                                showingSettings = false
                                            }
                                        }
                                    } else {
                                        // Is a git repo - set it normally
                                        UserDefaults.standard.set(path, forKey: "gitRepoPath")
                                        addToRecents(path)
                                        gitManager.refresh {
                                            showingSettings = false
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }

            HStack {
                Button("Wipe") {
                    showWipeConfirmation = true
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .foregroundColor(.secondary)
                .disabled(!githubAuthManager.isAuthenticated || gitManager.remoteUrl.isEmpty)
                .help("Reset repository to a single commit, erasing all history")
                
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
    
    func createRepoView(folderPath: String) -> some View {
        VStack(spacing: 12) {
            // Header - matching settings/history style
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("Create Repository")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button("Cancel") {
                    createRepoPath = nil
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            .padding(.top, 4)
            
            Divider()
                .padding(.top, 4)
            
            // Content
            CreateRepoContentView(
                folderPath: folderPath,
                onDismiss: { createRepoPath = nil },
                onSuccess: { path in
                    UserDefaults.standard.set(path, forKey: "gitRepoPath")
                    addToRecents(path)
                    createRepoPath = nil
                    // Force immediate refresh to show new remote URL
                    gitManager.updateRemoteUrl()
                    gitManager.refresh()
                }
            )
            .environmentObject(gitManager)
            .environmentObject(githubAuthManager)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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
                        CommitRowView(
                            commit: commit,
                            isCurrentCommit: commit.id == gitManager.currentHash,
                            isFutureCommit: isCommitInFuture(commit),
                            onTap: {
                                if commit.id != gitManager.currentHash {
                                    gitManager.resetToCommit(commit.id)
                                }
                            }
                        )
                        
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

// Separate view for commit row to handle hover state
struct CommitRowView: View {
    let commit: Commit
    let isCurrentCommit: Bool
    let isFutureCommit: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Text(commit.message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isFutureCommit ? .blue : .primary)
                
                Spacer(minLength: 0)
                
                if isFutureCommit {
                    Text("Future")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                        .fixedSize()
                }
                
                Text(commit.date)
                    .font(.system(size: 10))
                    .foregroundColor(isFutureCommit ? .blue.opacity(0.7) : .secondary)
                    .fixedSize()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(
            isCurrentCommit ? Color.primary.opacity(0.05) :
            isHovered ? Color.primary.opacity(0.03) : Color.clear
        )
        .cornerRadius(4)
        .onHover { inside in
            isHovered = inside
            if inside && !isCurrentCommit {
                NSCursor.pointingHand.push()
            } else if !inside {
                NSCursor.pop()
            }
        }
    }
}

// Separate view for branch row with custom hover state and context menu
struct BranchRowView: View {
    let branchName: String
    let isCurrentBranch: Bool
    let onTap: () -> Void
    let onMerge: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRename: (() -> Void)?
    let currentBranchName: String
    
    @State private var isHovered = false
    
    init(branchName: String, isCurrentBranch: Bool, currentBranchName: String = "", onTap: @escaping () -> Void, onMerge: (() -> Void)? = nil, onDelete: (() -> Void)? = nil, onRename: (() -> Void)? = nil) {
        self.branchName = branchName
        self.isCurrentBranch = isCurrentBranch
        self.currentBranchName = currentBranchName
        self.onTap = onTap
        self.onMerge = onMerge
        self.onDelete = onDelete
        self.onRename = onRename
    }
    
    var body: some View {
        HStack {
            Text(branchName)
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            if isCurrentBranch {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Rename") {
                onRename?()
            }
            
            if !isCurrentBranch {
                if let onMerge = onMerge {
                    Button {
                        onMerge()
                    } label: {
                        Text("Merge into \(currentBranchName)")
                    }
                    .help("Take changes from \(branchName) and bring them into \(currentBranchName)")
                }
                
                Divider()
                
                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Text("Delete Branch")
                    }
                    .help("Permanently remove the branch \(branchName)")
                }
            }
        }
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct NewBranchButton: View {
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text("New Branch")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// Separate view for recent path row to handle hover state
struct RecentPathRowView: View {
    let displayText: String
    let fullPath: String
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullPath) // Show full path on hover
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.gray.opacity(0.15) : Color.gray.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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
