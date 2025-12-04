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
    }
    
    func refresh(completion: (() -> Void)? = nil) {
        updateLocalCommitCount()
        updateUncommittedFiles {
            self.updateBranchInfo {
                self.updateRemoteUrl()
                self.fetchCommitHistory()
                completion?()
            }
        }
    }

    func commitLocally(_ message: String) {
        isCommitting = true
        guard !storedRepoPath.isEmpty else {
            print("Error: No repository path configured in settings")
            isCommitting = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Add all changes
            let addResult = self.executeGitCommand(in: self.storedRepoPath, args: ["add", "."])
            if addResult.failure {
                print("Error adding files: \(addResult.output)")
                DispatchQueue.main.async { self.isCommitting = false }
                return
            }

            // Create commit locally
            let commitResult = self.executeGitCommand(in: self.storedRepoPath, args: ["commit", "-m", message])
            if commitResult.failure {
                print("Error creating commit: \(commitResult.output)")
                DispatchQueue.main.async { self.isCommitting = false }
                return
            }

            DispatchQueue.main.async {
                self.isCommitting = false
                self.updateLocalCommitCount()
                self.updateUncommittedFiles()
                self.updateBranchInfo()
                print("Created local commit: \(message)")
            }
        }
    }
    
    // MARK: - Repository Initialization
    
    func isGitRepository(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitPath)
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
        let commitResult = executeGitCommand(in: path, args: ["commit", "-m", message])
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
    
    func pushToNewRemote(at path: String) -> Bool {
        // Push with --set-upstream for new branch
        let result = executeGitCommand(in: path, args: ["push", "-u", "origin", "main"])
        if result.failure {
            print("Error pushing to remote: \(result.output)")
            return false
        }
        print("Successfully pushed to remote")
        return true
    }

    func pushToRemote() {
        guard commitCount > 0 else {
            print("No commits to push")
            return
        }
        guard !storedRepoPath.isEmpty else {
            print("Error: No repository path configured")
            return
        }

        // First try a normal push
        let pushResult = executeGitCommand(in: storedRepoPath, args: ["push"])
        
        // If normal push fails, check if it's because of diverged history
        if pushResult.failure {
            // Check if the error is about diverged branches (common after reset)
            if pushResult.output.contains("rejected") || pushResult.output.contains("diverged") || pushResult.output.contains("non-fast-forward") {
                print("History has diverged, attempting force push...")
                
                // Do a force push to overwrite remote history
                let forcePushResult = executeGitCommand(in: storedRepoPath, args: ["push", "--force"])
                
                if forcePushResult.failure {
                    print("Error force pushing to remote: \(forcePushResult.output)")
                    return
                }
                
                print("Successfully force pushed commits to remote")
            } else {
                print("Error pushing to remote: \(pushResult.output)")
                return
            }
        } else {
            print("Successfully pushed commits to remote")
        }

        updateLocalCommitCount()
        updateUncommittedFiles()
        updateBranchInfo()
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
                    url = url.replacingOccurrences(of: ":", with: "/")
                    url = url.replacingOccurrences(of: "git@", with: "https://")
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
            // Count commits that exist locally but not on remote
            let revListResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])

            if revListResult.failure {
                // Try with master branch if main doesn't exist
                let revListResultMaster = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/master"])
                if revListResultMaster.failure {
                    print("Error counting local commits: \(revListResult.output)")
                    DispatchQueue.main.async {
                        self.commitCount = 0
                        completion?()
                    }
                    return
                }
                if let count = Int(revListResultMaster.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    DispatchQueue.main.async {
                        self.commitCount = count
                        completion?()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.commitCount = 0
                        completion?()
                    }
                }
            } else {
                if let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    DispatchQueue.main.async {
                        self.commitCount = count
                        completion?()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.commitCount = 0
                        completion?()
                    }
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

            // Check if ahead of remote
            let revListResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])

            var isAhead = false
            if revListResult.failure {
                let revListResultMaster = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/master"])
                if !revListResultMaster.failure, let count = Int(revListResultMaster.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    isAhead = count > 0
                }
            } else if let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                isAhead = count > 0
            }

            // Get current hash
            let hashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "HEAD"])
            let hash = hashResult.failure ? "" : hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                self.currentBranch = branchName
                self.isAheadOfRemote = isAhead
                self.currentHash = hash
                
                // Detect detached HEAD state
                if branchName == "HEAD" {
                    self.isDetachedHead = true
                } else {
                    self.isDetachedHead = false
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
            let args = ["log", "--all", "--reflog", "--pretty=format:%H|%s|%ad|%an", "--date=short", "-n", "100"]
            
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
                    return Commit(id: hash, message: parts[1], date: parts[2], author: parts[3])
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

    private func executeGitCommand(in directory: String, args: [String]) -> (output: String, failure: Bool) {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = args
        task.currentDirectoryPath = directory

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return ("Failed to execute git command: \(error.localizedDescription)", true)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        let status = task.terminationStatus

        return (output, status != 0)
    }
}
