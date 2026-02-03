//
//  GitManager.swift
//  GitMenuBar
//

import Foundation
import AppKit

struct Commit: Identifiable {
    let id: String
    let message: String
    let date: String
    let author: String
}

class GitManager: ObservableObject {
    @Published var commitCount: Int = 0
    @Published var isCommitting: Bool = false
    @Published var uncommittedFiles: [String] = []
    @Published var currentBranch: String = "main"
    @Published var isAheadOfRemote: Bool = false
    @Published var remoteUrl: String = ""
    @Published var commitHistory: [Commit] = []
    @Published var isDetachedHead: Bool = false
    @Published var currentHash: String = ""
    @Published var lastActiveBranch: String = ""
    @Published var availableBranches: [String] = []
    @Published var isRemoteAhead: Bool = false
    @Published var isBehindRemote: Bool = false
    @Published var remoteBranchName: String = ""
    @Published var behindCount: Int = 0
    @Published var isPrivate: Bool = false
    
    /// Token provider for authenticated git operations (push/pull)
    var tokenProvider: (() -> String?)?
    
    /// GitHub API client for checking repo existence
    var githubAPIClient: GitHubAPIClient?
    
    /// Path to the askpass helper script
    private var askpassScriptPath: String?

    private var storedRepoPath: String {
        get {
            UserDefaults.standard.string(forKey: "gitRepoPath") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "gitRepoPath")
        }
    }

    init() {
        updateLocalCommitCount()
        updateUncommittedFiles()
        updateUncommittedFiles()
        updateBranchInfo()
        updateRemoteUrl()
        fetchCommitHistory()
        fetchBranches()
    }
    
    func refresh(completion: (() -> Void)? = nil) {
        updateLocalCommitCount()
        updateUncommittedFiles {
            self.updateBranchInfo {
                self.updateRemoteUrl()
                self.fetchCommitHistory()
                self.fetchBranches()
                self.checkRemoteStatus()
                self.checkRepoVisibility()
                completion?()
            }
        }
    }

    func commitLocally(_ message: String, skipUIUpdates: Bool = false, completion: (() -> Void)? = nil) {
        isCommitting = true
        guard !storedRepoPath.isEmpty else {
            print("Error: No repository path configured in settings")
            isCommitting = false
            completion?()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Add all changes
            let addResult = self.executeGitCommand(in: self.storedRepoPath, args: ["add", "."])
            if addResult.failure {
                print("Error adding files: \(addResult.output)")
                DispatchQueue.main.async { 
                    self.isCommitting = false 
                    completion?()
                }
                return
            }

            // Create commit locally
            let commitResult = self.executeGitCommand(in: self.storedRepoPath, args: ["commit", "--no-gpg-sign", "-m", message])
            if commitResult.failure {
                print("Error creating commit: \(commitResult.output)")
                DispatchQueue.main.async { 
                    self.isCommitting = false 
                    completion?()
                }
                return
            }

            DispatchQueue.main.async {
                self.isCommitting = false
                // Only update UI if we're not about to close the popover
                if !skipUIUpdates {
                    self.updateLocalCommitCount()
                    self.updateUncommittedFiles()
                    self.updateBranchInfo()
                }
                print("Created local commit: \(message)")
                completion?()
            }
        }
    }
    
    // MARK: - Repository Initialization
    
    func isGitRepository(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitPath)
    }
    
    func hasRemoteConfigured(at path: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["config", "--get", "remote.origin.url"])
        return !result.failure && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Check if the remote repository actually exists on GitHub
    func remoteRepositoryExists(at path: String, completion: @escaping (Bool) -> Void) {
        // First check if remote is configured
        guard hasRemoteConfigured(at: path) else {
            completion(false)
            return
        }
        
        // Get the remote URL
        let result = executeGitCommand(in: path, args: ["config", "--get", "remote.origin.url"])
        guard !result.failure else {
            completion(false)
            return
        }
        
        let remoteURL = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse owner and repo from URL
        // Supports formats like:
        // - https://github.com/owner/repo
        // - https://github.com/owner/repo.git
        // - git@github.com:owner/repo.git
        
        var urlToParse = remoteURL
        
        // Convert SSH to HTTPS format for easier parsing
        if urlToParse.hasPrefix("git@") {
            let parts = urlToParse.components(separatedBy: ":")
            if parts.count > 1 {
                let path = parts.dropFirst().joined(separator: ":")
                urlToParse = "https://github.com/" + path
            }
        }
        
        // Remove .git suffix
        if urlToParse.hasSuffix(".git") {
            urlToParse = String(urlToParse.dropLast(4))
        }
        
        // Extract owner and repo from URL
        guard let url = URL(string: urlToParse),
              url.host?.contains("github.com") == true else {
            // Not a GitHub URL, assume it exists
            completion(true)
            return
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else {
            completion(false)
            return
        }
        
        let owner = pathComponents[0]
        let repo = pathComponents[1]
        
        // Check if repo exists using GitHub API
        guard let apiClient = githubAPIClient else {
            // No API client available, assume exists
            completion(true)
            return
        }
        
        Task {
            let exists = await apiClient.checkRepositoryURLExists(owner: owner, repo: repo)
            DispatchQueue.main.async {
                completion(exists)
            }
        }
    }
    
    func initializeRepository(at path: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["init"])
        if result.failure {
            print("Error initializing repository: \(result.output)")
            return false
        }
        print("Initialized git repository at: \(path)")
        return true
    }
    
    func createInitialCommit(at path: String, message: String) -> Bool {
        // Stage all files
        let addResult = executeGitCommand(in: path, args: ["add", "."])
        if addResult.failure {
            print("Error staging files: \(addResult.output)")
            return false
        }
        
        // Create initial commit
        let commitResult = executeGitCommand(in: path, args: ["commit", "--no-gpg-sign", "-m", message])
        if commitResult.failure {
            print("Error creating initial commit: \(commitResult.output)")
            return false
        }
        
        print("Created initial commit: \(message)")
        return true
    }
    
    func addRemote(at path: String, url: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["remote", "add", "origin", url])
        if result.failure {
            print("Error adding remote: \(result.output)")
            return false
        }
        print("Added remote origin: \(url)")
        return true
    }
    
    func hasUncommittedChanges(at path: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["status", "--porcelain"])
        return !result.failure && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func updateRemoteURL(at path: String, newURL: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["remote", "set-url", "origin", newURL])
        return !result.failure
    }
    
    func pushToNewRemote(at path: String) -> Bool {
        // Push with --set-upstream for new branch
        let result = executeGitCommand(in: path, args: ["push", "-u", "origin", "main"], useAuth: true)
        if result.failure {
            print("Error pushing to remote: \(result.output)")
            return false
        }
        print("Successfully pushed to remote")
        return true
    }

    func pushToRemote(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Use current branch as target
        pushToBranch(branchName: currentBranch, force: false, completion: completion)
    }
    
    func pushToBranch(branchName: String, force: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            let error = NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error: No repository path configured"])
            print(error.localizedDescription)
            DispatchQueue.main.async {
                completion?(.failure(error))
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Determine push arguments
            var pushArgs: [String]
            
            if branchName == self.currentBranch {
                // Pushing current branch - always use -u to set/update upstream
                pushArgs = force ? ["push", "--force", "-u", "origin", branchName] : ["push", "-u", "origin", branchName]
            } else {
                // Pushing current HEAD to a different remote branch
                pushArgs = force ? ["push", "--force", "origin", "HEAD:\(branchName)"] : ["push", "origin", "HEAD:\(branchName)"]
            }
            
            let pushResult = self.executeGitCommand(in: self.storedRepoPath, args: pushArgs, useAuth: true)
            
            // If normal push fails, check if it's because of diverged history
            if pushResult.failure {
                // Check if the error is about diverged branches (common after reset)
                if pushResult.output.contains("rejected") || pushResult.output.contains("diverged") || pushResult.output.contains("non-fast-forward") {
                    print("History has diverged, attempting force push...")
                    
                    // Do a force push to overwrite remote history
                    let forcePushArgs = branchName == self.currentBranch ? ["push", "--force", "-u", "origin", branchName] : ["push", "--force", "origin", "HEAD:\(branchName)"]
                    let forcePushResult = self.executeGitCommand(in: self.storedRepoPath, args: forcePushArgs, useAuth: true)
                    
                    if forcePushResult.failure {
                        let error = NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error force pushing: \(forcePushResult.output)"])
                        print(error.localizedDescription)
                        DispatchQueue.main.async {
                            completion?(.failure(error))
                        }
                        return
                    }
                    
                    print("Successfully force pushed commits to remote")
                } else {
                    let error = NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Error pushing: \(pushResult.output)"])
                    print(error.localizedDescription)
                    DispatchQueue.main.async {
                        completion?(.failure(error))
                    }
                    return
                }
            } else {
                print("Successfully pushed commits to remote")
            }

            // Success
            DispatchQueue.main.async {
                completion?(.success(()))
            }
        }
    }
    
    func updateRemoteUrl() {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.remoteUrl = ""
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["config", "--get", "remote.origin.url"])
            
            if !result.failure {
                var url = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Convert SSH to HTTPS if needed
                if url.hasPrefix("git@") {
                    // Handle git@host:user/repo.git format
                    // This handles both standard github.com and SSH aliases (e.g. github-digging)
                    // by extracting the path and forcing github.com
                    let parts = url.components(separatedBy: ":")
                    if parts.count > 1 {
                        // Take everything after the first colon (user/repo.git)
                        let path = parts.dropFirst().joined(separator: ":")
                        url = "https://github.com/" + path
                    } else {
                        // Fallback for unexpected formats
                        url = url.replacingOccurrences(of: ":", with: "/")
                        url = url.replacingOccurrences(of: "git@", with: "https://")
                    }
                }
                
                // Remove .git suffix if present
                if url.hasSuffix(".git") {
                    url = String(url.dropLast(4))
                }
                
                DispatchQueue.main.async {
                    self.remoteUrl = url
                }
            } else {
                DispatchQueue.main.async {
                    self.remoteUrl = ""
                }
            }
        }
    }

    func updateLocalCommitCount(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.commitCount = 0
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Count commits that exist locally but not on remote (ahead of upstream)
            // uses @{u}..HEAD which calculates commits in HEAD not in upstream
            let revListResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "@{u}..HEAD"])

            if revListResult.failure {
                // Fallback: if no upstream configured, check against origin/main directly
                // (Previous logic, kept as fallback)
                let revListFallback = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])
                
                if let count = Int(revListFallback.output.trimmingCharacters(in: .whitespacesAndNewlines)), !revListFallback.failure {
                     DispatchQueue.main.async {
                        self.commitCount = count
                        completion?()
                    }
                } else {
                     // Try with master
                    let revListMaster = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/master"])
                    let count = Int(revListMaster.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    
                     DispatchQueue.main.async {
                        self.commitCount = count
                        completion?()
                    }
                }
            } else {
                let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                DispatchQueue.main.async {
                    self.commitCount = count
                    completion?()
                }
            }
        }
    }

    func updateUncommittedFiles(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.uncommittedFiles = []
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Get list of modified/untracked files
            let statusResult = self.executeGitCommand(in: self.storedRepoPath, args: ["status", "--porcelain"])

            if statusResult.failure {
                print("Error getting git status: \(statusResult.output)")
                DispatchQueue.main.async {
                    self.uncommittedFiles = []
                    completion?()
                }
                return
            }

            let files = statusResult.output
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { line in
                    // Remove status code and space, return just the filename
                    return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }

            DispatchQueue.main.async {
                self.uncommittedFiles = files
                completion?()
            }
        }
    }

    func updateBranchInfo(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.currentBranch = "main"
                self.isAheadOfRemote = false
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Get current branch
            let branchResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])

            let branchName = branchResult.failure ? "main" : branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if ahead of remote using upstream tracking
            let revListResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "@{u}..HEAD"])

            var isAhead = false
            if revListResult.failure {
                // Fallback checks
                 let revListMain = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])
                 if !revListMain.failure, let count = Int(revListMain.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                     isAhead = count > 0
                 } else {
                     let revListMaster = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/master"])
                     if !revListMaster.failure, let count = Int(revListMaster.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                         isAhead = count > 0
                     }
                 }
            } else if let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                isAhead = count > 0
            }

            // Get current hash
            let hashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "HEAD"])
            let hash = hashResult.failure ? "" : hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                self.isAheadOfRemote = isAhead
                self.currentHash = hash
                
                // Detect detached HEAD state
                if branchName == "HEAD" {
                    self.isDetachedHead = true
                    // Try to get a nicer name like (detached at <short_hash>)
                    let shortHashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "--short", "HEAD"])
                    if !shortHashResult.failure {
                        self.currentBranch = "(detached at \(shortHashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)))"
                    } else {
                        self.currentBranch = "(detached)"
                    }
                } else {
                    self.isDetachedHead = false
                    self.currentBranch = branchName
                    self.lastActiveBranch = branchName
                }
                
                completion?()
            }
        }
    }

    func resetToLastCommit() {
        guard !storedRepoPath.isEmpty else {
            print("Error: No repository path configured")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Reset to last commit (discard all changes)
            let resetResult = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "--hard", "HEAD"])

            if resetResult.failure {
                print("Error resetting to last commit: \(resetResult.output)")
                return
            }

            // Update status
            self.updateLocalCommitCount()
            self.updateUncommittedFiles()
            self.updateBranchInfo()
            print("Reset to last commit")
        }
    }

    func fetchCommitHistory() {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.commitHistory = []
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Get all commits including "future" ones from reflog
            // This shows commits even if we've reset backwards
            // Use Unix timestamp (%at) for unambiguous time parsing
            let args = ["log", "--all", "--reflog", "--pretty=format:%H|%s|%at|%an", "-n", "100"]
            
            let result = self.executeGitCommand(in: self.storedRepoPath, args: args)
            
            if !result.failure {
                var seenHashes = Set<String>()
                let commits = result.output.components(separatedBy: .newlines).compactMap { line -> Commit? in
                    let parts = line.components(separatedBy: "|")
                    guard parts.count >= 4 else { return nil }
                    let hash = parts[0]
                    // Skip duplicate commits (reflog can show same commit multiple times)
                    guard !seenHashes.contains(hash) else { return nil }
                    seenHashes.insert(hash)
                    
                    // Parse timestamp
                    guard let timestamp = TimeInterval(parts[2]) else { return nil }
                    let startOfDate = Date(timeIntervalSince1970: timestamp)
                    
                    // Format date
                    let formattedDate = self.formatCommitDate(startOfDate)
                    
                    return Commit(id: hash, message: parts[1], date: formattedDate, author: parts[3])
                }
                
                DispatchQueue.main.async {
                    self.commitHistory = commits
                }
            } else {
                DispatchQueue.main.async {
                    self.commitHistory = []
                }
            }
        }
    }
    
    private func formatCommitDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            // Show time for today's commits - respects system 12/24h setting
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.dateStyle = .none
            return timeFormatter.string(from: date)
        } else {
            // Show date for older commits - respects locale order
            let dateFormatter = DateFormatter()
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
            return dateFormatter.string(from: date)
        }
    }

    
    func resetToCommit(_ hash: String) {
        guard !storedRepoPath.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Do a hard reset to the specified commit while staying on the current branch
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "--hard", hash])
            
            if result.failure {
                print("Error resetting to commit: \(result.output)")
            } else {
                DispatchQueue.main.async {
                    self.refresh()
                    print("Reset to commit: \(hash)")
                }
            }
        }
    }

    /// Wipes the repository history, leaving only a single "Initial commit" with current files
    /// Uses the orphan branch approach to completely remove all history
    func wipeRepository(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Step 0a: Ensure .git-backup-* is in .gitignore before creating backup
            let gitignorePath = (self.storedRepoPath as NSString).appendingPathComponent(".gitignore")
            let backupIgnorePattern = ".git-backup-*"
            
            do {
                var gitignoreContent = ""
                if FileManager.default.fileExists(atPath: gitignorePath) {
                    gitignoreContent = try String(contentsOfFile: gitignorePath, encoding: .utf8)
                }
                
                // Check if pattern already exists
                if !gitignoreContent.contains(backupIgnorePattern) {
                    // Add the pattern (with newline if file doesn't end with one)
                    if !gitignoreContent.isEmpty && !gitignoreContent.hasSuffix("\n") {
                        gitignoreContent += "\n"
                    }
                    gitignoreContent += backupIgnorePattern + "\n"
                    try gitignoreContent.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
                    print("Added \(backupIgnorePattern) to .gitignore")
                }
            } catch {
                print("Warning: Could not update .gitignore: \(error.localizedDescription)")
                // Continue anyway - not a fatal error
            }
            
            // Step 0b: Backup the .git folder before wiping
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let gitPath = (self.storedRepoPath as NSString).appendingPathComponent(".git")
            let backupPath = (self.storedRepoPath as NSString).appendingPathComponent(".git-backup-\(timestamp)")
            
            do {
                try FileManager.default.copyItem(atPath: gitPath, toPath: backupPath)
                print("Backed up .git folder to: \(backupPath)")
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to backup .git folder: \(error.localizedDescription)"])))
                }
                return
            }
            
            // Step 1: Detect current branch to wipe
            let branchParseResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            if branchParseResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to detect current branch: \(branchParseResult.output)"])))
                }
                return
            }
            
            let branchToWipe = branchParseResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Do not allow wiping in detached HEAD state
            if branchToWipe == "HEAD" {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot wipe in detached HEAD state. Please checkout a branch first."])))
                }
                return
            }

            // Step 2: Create an orphan branch (no history)
            let orphanResult = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "--orphan", "temp_wipe_branch"])
            if orphanResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create orphan branch: \(orphanResult.output)"])))
                }
                return
            }
            
            // Step 3: Stage all current files
            let addResult = self.executeGitCommand(in: self.storedRepoPath, args: ["add", "-A"])
            if addResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to stage files: \(addResult.output)"])))
                }
                return
            }
            
            // Step 4: Create the fresh "Initial commit"
            let commitResult = self.executeGitCommand(in: self.storedRepoPath, args: ["commit", "--no-gpg-sign", "-m", "Initial commit"])
            if commitResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create initial commit: \(commitResult.output)"])))
                }
                return
            }
            
            // Step 5: Delete the old branch
            let deleteBranchResult = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-D", branchToWipe])
            if deleteBranchResult.failure {
                print("Warning: Could not delete old branch \(branchToWipe): \(deleteBranchResult.output)")
            }
            
            // Step 6: Rename current branch to the original branch name
            let renameResult = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-m", branchToWipe])
            if renameResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to rename branch to \(branchToWipe): \(renameResult.output)"])))
                }
                return
            }
            
            // Step 7: Force push to remote to overwrite history (use -u to set upstream tracking)
            let forcePushResult = self.executeGitCommand(in: self.storedRepoPath, args: ["push", "-u", "-f", "origin", branchToWipe], useAuth: true)
            if forcePushResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to force push to \(branchToWipe): \(forcePushResult.output)"])))
                }
                return
            }
            
            // Step 7: Clean up old objects (optional but thorough)
            _ = self.executeGitCommand(in: self.storedRepoPath, args: ["gc", "--prune=now"])
            
            // Success - refresh the UI
            DispatchQueue.main.async {
                self.refresh()
                completion(.success(()))
            }
        }
    }

    private func executeGitCommand(in directory: String, args: [String], useAuth: Bool = false) -> (output: String, failure: Bool) {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = args
        task.currentDirectoryPath = directory
        
        // Set up environment with authentication if needed
        if useAuth, let token = tokenProvider?() {
            var env = ProcessInfo.processInfo.environment
            
            // Create a temporary askpass script
            let scriptPath = createAskpassScript(token: token)
            if let scriptPath = scriptPath {
                env["GIT_ASKPASS"] = scriptPath
                env["GIT_TERMINAL_PROMPT"] = "0"
                task.environment = env
                self.askpassScriptPath = scriptPath
            }
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            cleanupAskpassScript()
            return ("Failed to execute git command: \(error.localizedDescription)", true)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        let status = task.terminationStatus
        
        cleanupAskpassScript()

        return (output, status != 0)
    }
    
    private func createAskpassScript(token: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("git-askpass-\(UUID().uuidString).sh").path
        
        // The script echoes the token as the password
        let scriptContent = "#!/bin/bash\necho \"\(token)\""
        
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            // Make executable
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
            return scriptPath
        } catch {
            print("Failed to create askpass script: \(error)")
            return nil
        }
    }
    
    private func cleanupAskpassScript() {
        if let path = askpassScriptPath {
            try? FileManager.default.removeItem(atPath: path)
            askpassScriptPath = nil
        }
    }
    
    // MARK: - Branch Management
    
    func fetchBranches(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.availableBranches = []
                completion?()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Get all branches (local and remote)
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-a", "--format=%(refname:short)"])
            
            if !result.failure {
                var branches = result.output
                    .components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                    .map { branch in
                        // Clean up remote branch names
                        if branch.hasPrefix("origin/") {
                            return String(branch.dropFirst(7)) // Remove "origin/"
                        }
                        return branch
                    }
                    .filter { $0 != "HEAD" && $0 != "origin" && !$0.contains("origin/HEAD") } // Remove HEAD and confusing origin entries
                
                // Remove duplicates (local + remote same branch)
                branches = Array(Set(branches)).sorted()
                
                DispatchQueue.main.async {
                    self.availableBranches = branches
                    completion?()
                }
            } else {
                DispatchQueue.main.async {
                    self.availableBranches = []
                    completion?()
                }
            }
        }
    }
    
    func checkRemoteStatus(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.isRemoteAhead = false
                self.isBehindRemote = false
                self.behindCount = 0
                completion?()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // First, fetch to update remote refs (do this quietly)
            _ = self.executeGitCommand(in: self.storedRepoPath, args: ["fetch"], useAuth: true)
            
            // Check if we're ahead or behind remote
            // Format: "behind\tahead" (e.g., "2\t3" means 2 behind, 3 ahead)
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--left-right", "--count", "@{u}...HEAD"])
            
            if !result.failure {
                let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
                if parts.count == 2 {
                    let behind = Int(parts[0]) ?? 0
                    let ahead = Int(parts[1]) ?? 0
                    
                    DispatchQueue.main.async {
                        self.behindCount = behind
                        self.isRemoteAhead = behind > 0
                        self.isBehindRemote = behind > 0
                        completion?()
                    }
                    return
                }
            }
            
            // Fallback: no upstream or error
            DispatchQueue.main.async {
                self.isRemoteAhead = false
                self.isBehindRemote = false
                self.behindCount = 0
                completion?()
            }
        }
    }
    
    func checkRepoVisibility(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.isPrivate = false
                completion?()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Get URL from config to be sure
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["config", "--get", "remote.origin.url"])
            guard !result.failure else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }
            
            let remoteURL = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse owner and repo
            var urlToParse = remoteURL
            if urlToParse.hasPrefix("git@") {
                let parts = urlToParse.components(separatedBy: ":")
                if parts.count > 1 {
                    let path = parts.dropFirst().joined(separator: ":")
                    urlToParse = "https://github.com/" + path
                }
            }
            
            if urlToParse.hasSuffix(".git") {
                urlToParse = String(urlToParse.dropLast(4))
            }
            
            guard let url = URL(string: urlToParse),
                  let host = url.host,
                  host.contains("github.com") else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }
            
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard pathComponents.count >= 2 else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }
            
            let owner = pathComponents[0]
            let repo = pathComponents[1]
            
            guard let apiClient = self.githubAPIClient else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }
            
            Task {
                do {
                    let repository = try await apiClient.getRepository(owner: owner, name: repo)
                    DispatchQueue.main.async {
                        self.isPrivate = repository.private
                        completion?()
                    }
                } catch {
                    print("Error checking repo visibility: \(error)")
                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            }
        }
    }

    func pullFromRemote(rebase: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let args = rebase ? ["pull", "--rebase"] : ["pull"]
            let result = self.executeGitCommand(in: self.storedRepoPath, args: args, useAuth: true)
            
            if result.failure {
                // Check if it's a merge conflict
                if result.output.contains("CONFLICT") || result.output.contains("conflict") {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Merge conflict - please resolve manually"])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Pull failed: \(result.output)"])))
                    }
                }
            } else {
                print("Successfully pulled from remote")
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            }
        }
    }
    
    func pullToNewBranch(newBranchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Create a new branch originating from the upstream branch of our current branch
            // git checkout -b <newBranchName> @{u}
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "-b", newBranchName, "@{u}"])
            
            if result.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create branch from remote: \(result.output)"])))
                }
            } else {
                print("Successfully created branch \(newBranchName) from remote")
                DispatchQueue.main.async {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    func createBranchFromCurrentHead(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Branch name cannot be empty"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Create and checkout new branch from HEAD
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "-b", trimmedName])
            
            if result.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create branch: \(result.output)"])))
                }
            } else {
                print("Successfully created and switched to branch \(trimmedName)")
                DispatchQueue.main.async {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func switchBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Check if we have uncommitted changes
            let statusResult = self.executeGitCommand(in: self.storedRepoPath, args: ["status", "--porcelain"])
            let hasChanges = !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            var stashCreated = false
            
            // If we have changes, stash them first
            if hasChanges {
                let stashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "push", "-u", "-m", "GitMenuBar auto-stash for branch switch"])
                
                if stashResult.failure {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to save changes: \(stashResult.output)"])))
                    }
                    return
                }
                stashCreated = true
                print("Stashed changes before switching branches")
            }
            
            // Try to switch/checkout branch
            let checkoutResult = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", branchName])
            
            if checkoutResult.failure {
                // If checkout failed and we stashed, try to restore the stash
                if stashCreated {
                    _ = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "pop"])
                }
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to switch branch: \(checkoutResult.output)"])))
                }
                return
            }
            
            print("Successfully switched to branch: \(branchName)")
            
            // If we stashed changes, restore them
            if stashCreated {
                let popResult = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "pop"])
                
                if popResult.failure {
                    // Stash pop failed - likely due to conflicts
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Switched branches, but couldn't reapply your changes due to conflicts. Run 'git stash pop' manually to resolve."])))
                    }
                    return
                }
                print("Restored stashed changes after branch switch")
            }
            
            // Refresh all status after switch
            DispatchQueue.main.async {
                self.refresh {
                    completion(.success(()))
                }
            }
        }
    }
    
    func createBranch(branchName: String, fromBranch: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        // Validate branch name (basic validation)
        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Branch name cannot be empty"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Create branch from specified branch or current HEAD
            var args = ["checkout", "-b", trimmedName]
            if let fromBranch = fromBranch, !fromBranch.isEmpty {
                args.append(fromBranch)
            }
            
            let result = self.executeGitCommand(in: self.storedRepoPath, args: args)
            
            if result.failure {
                // Parse common error cases for friendly messages
                let output = result.output
                var friendlyMessage = "Failed to create branch"
                
                if output.contains("already exists") {
                    friendlyMessage = "Branch '\(trimmedName)' already exists"
                } else if output.contains("not a valid branch name") || output.contains("invalid ref format") {
                    friendlyMessage = "Invalid branch name"
                } else if output.contains("not found") || output.contains("does not exist") {
                    friendlyMessage = "Source branch not found"
                } else {
                    // Show a trimmed version of the error for unexpected cases
                    let errorSnippet = output.components(separatedBy: "\n").first ?? output
                    friendlyMessage = errorSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: friendlyMessage])))
                }
            } else {
                print("Successfully created and switched to branch: \(trimmedName)")
                // Refresh all status after creating branch
                DispatchQueue.main.async {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    func mergeBranch(fromBranch: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Perform the merge
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["merge", fromBranch])
            
            if result.failure {
                // Check if it's a merge conflict
                if result.output.contains("CONFLICT") || result.output.contains("Automatic merge failed") {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Merge conflict! Please resolve manually."])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to merge: \(result.output)"])))
                    }
                }
            } else {
                print("Successfully merged \(fromBranch) into current branch")
                // Refresh all status after merge
                DispatchQueue.main.async {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    func deleteBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        // Don't allow deleting current branch
        if branchName == currentBranch {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot delete the currently checked out branch"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Try to delete the branch locally first
            let localResult = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-D", branchName])
            
            let localBranchExists = !localResult.failure || !localResult.output.contains("not found")
            
            if localResult.failure && localBranchExists {
                // Local deletion failed for a reason other than "not found"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to delete local branch: \(localResult.output)"])))
                }
                return
            }
            
            if !localResult.failure {
                print("Successfully deleted local branch: \(branchName)")
            } else {
                print("Local branch '\(branchName)' doesn't exist, will delete from remote only")
            }
            
            // Also delete from remote (GitHub) if it exists there
            let remoteResult = self.executeGitCommand(in: self.storedRepoPath, args: ["push", "origin", "--delete", branchName])
            
            // Don't fail if remote deletion fails (branch might not exist on remote)
            if remoteResult.failure && !remoteResult.output.contains("remote ref does not exist") {
                print("Note: Could not delete from remote: \(remoteResult.output)")
            } else {
                print("Successfully deleted remote branch: \(branchName)")
            }
            
            // Explicitly refresh branch list to update UI immediately
            DispatchQueue.main.async {
                self.fetchBranches {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    
    
    func renameBranch(oldName: String, newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }
        
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "New branch name cannot be empty"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Rename branch (using -m)
            // If it's the current branch, we don't need to specify the old name, but providing it works too
    
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-m", oldName, trimmedNewName])
            
            if result.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to rename branch: \(result.output)"])))
                }
            } else {
                print("Successfully renamed branch from \(oldName) to \(trimmedNewName)")
                DispatchQueue.main.async {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }
}
