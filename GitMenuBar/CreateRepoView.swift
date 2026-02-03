//
//  CreateRepoView.swift
//  GitMenuBar
//

import SwiftUI

// Content view for creating a repository - designed to be embedded inline
struct CreateRepoContentView: View {
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    
    let folderPath: String
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    @State private var repoName: String
    @State private var isPrivate: Bool = true
    @State private var isCreating: Bool = false
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    init(folderPath: String, onDismiss: @escaping () -> Void, onSuccess: @escaping (String) -> Void) {
        self.folderPath = folderPath
        self.onDismiss = onDismiss
        self.onSuccess = onSuccess
        // Pre-fill with folder name
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        _repoName = State(initialValue: folderName)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Folder info section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Folder")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(URL(fileURLWithPath: folderPath).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }
            
            // Repository name section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Repository Name")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                
                TextField("my-awesome-project", text: $repoName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            
            // Visibility section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: isPrivate ? "lock" : "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Visibility")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                
                HStack(spacing: 0) {
                    Button(action: { isPrivate = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                            Text("Public")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(!isPrivate ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundColor(!isPrivate ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { isPrivate = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock")
                                .font(.system(size: 10))
                            Text("Private")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(isPrivate ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundColor(isPrivate ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            
            // Error message
            if showError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }
            
            Spacer()
                .frame(height: 4)
            
            // Create button - full width, prominent
            Button(action: createRepository) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Creating...")
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Create & Publish to GitHub")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating ? Color.gray.opacity(0.3) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
        }
    }
    
    private func createRepository() {
        let trimmedName = repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isCreating = true
        showError = false
        
        Task {
            do {
                // Create GitHub API client
                let apiClient = GitHubAPIClient(authManager: githubAuthManager)
                
                // Step 1: Try to create repository on GitHub, or fetch existing one
                var repo: GitHubRepository
                do {
                    repo = try await apiClient.createRepository(
                        name: trimmedName,
                        isPrivate: isPrivate,
                        description: nil
                    )
                } catch GitHubAPIError.conflict {
                    // Repository already exists - fetch it instead
                    repo = try await apiClient.getRepository(name: trimmedName)
                }
                
                // Step 2: Initialize local git repository (only if not already initialized)
                let isGitRepo = gitManager.isGitRepository(at: folderPath)
                if !isGitRepo {
                    guard gitManager.initializeRepository(at: folderPath) else {
                        showErrorMessage("Failed to initialize local git repository")
                        return
                    }
                    
                    // Step 3: Create initial commit (only for newly initialized repos)
                    guard gitManager.createInitialCommit(at: folderPath, message: "Initial commit") else {
                        showErrorMessage("Failed to create initial commit")
                        return
                    }
                } else {
                    // Repository already exists - check if there are uncommitted changes
                    // If there are, commit them
                    if gitManager.hasUncommittedChanges(at: folderPath) {
                        // There are uncommitted changes - commit them
                        guard gitManager.createInitialCommit(at: folderPath, message: "Initial commit") else {
                            showErrorMessage("Failed to commit existing changes")
                            return
                        }
                    }
                    // If no uncommitted changes, we can proceed (there must be at least one commit already)
                }
                
                // Step 4: Add or update GitHub remote
                let hasRemote = gitManager.hasRemoteConfigured(at: folderPath)
                if hasRemote {
                    // Update existing remote
                    guard gitManager.updateRemoteURL(at: folderPath, newURL: repo.cloneUrl) else {
                        showErrorMessage("Failed to update remote URL")
                        return
                    }
                } else {
                    // Add new remote
                    guard gitManager.addRemote(at: folderPath, url: repo.cloneUrl) else {
                        showErrorMessage("Failed to add remote")
                        return
                    }
                }
                
                // Step 5: Push to GitHub
                guard gitManager.pushToNewRemote(at: folderPath) else {
                    showErrorMessage("Failed to push to GitHub")
                    return
                }
                
                // Success! Refresh git manager to update UI with new remote URL
                await MainActor.run {
                    gitManager.refresh()
                    onSuccess(folderPath)
                }
                
            } catch let error as GitHubAPIError {
                switch error {
                case .unauthorized:
                    showErrorMessage("GitHub authentication failed. Please reconnect.")
                case .rateLimitExceeded:
                    showErrorMessage("GitHub rate limit exceeded. Please try again later.")
                case .networkError(let err):
                    showErrorMessage("Network error: \(err.localizedDescription)")
                default:
                    showErrorMessage("Failed to create repository: \(error)")
                }
            } catch {
                showErrorMessage("Unexpected error: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        isCreating = false
    }
}
