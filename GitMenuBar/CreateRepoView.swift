//
//  CreateRepoView.swift
//  GitMenuBar
//

import SwiftUI

struct CreateRepoView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    
    let folderPath: String
    
    @State private var repoName: String
    @State private var isPrivate: Bool = true
    @State private var isCreating: Bool = false
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    init(folderPath: String) {
        self.folderPath = folderPath
        // Pre-fill with folder name
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        _repoName = State(initialValue: folderName)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            HStack {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                Text("Create & Publish Repository")
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, 8)
            
            Divider()
            
            // Folder path info
            VStack(alignment: .leading, spacing: 4) {
                Text("Folder:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(folderPath)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Repository name
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository Name:")
                    .font(.system(size: 12, weight: .medium))
                TextField("my-awesome-project", text: $repoName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            
            // Privacy toggle
            HStack {
                Text("Visibility:")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                Picker("", selection: $isPrivate) {
                    Text("Public").tag(false)
                    Text("Private").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            
            // Error message
            if showError {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(isCreating ? "Creating..." : "Create & Publish") {
                    createRepository()
                }
                .buttonStyle(.borderedProminent)
                .disabled(repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 450)
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
                
                // Step 1: Create repository on GitHub
                let repo = try await apiClient.createRepository(
                    name: trimmedName,
                    isPrivate: isPrivate,
                    description: nil
                )
                
                // Step 2: Initialize local git repository
                guard gitManager.initializeRepository(at: folderPath) else {
                    await showErrorMessage("Failed to initialize local git repository")
                    return
                }
                
                // Step 3: Create initial commit
                guard gitManager.createInitialCommit(at: folderPath, message: "Initial commit") else {
                    await showErrorMessage("Failed to create initial commit")
                    return
                }
                
                // Step 4: Add GitHub remote
                guard gitManager.addRemote(at: folderPath, url: repo.cloneUrl) else {
                    await showErrorMessage("Failed to add remote")
                    return
                }
                
                // Step 5: Push to GitHub
                guard gitManager.pushToNewRemote(at: folderPath) else {
                    await showErrorMessage("Failed to push to GitHub")
                    return
                }
                
                // Success! Update the repo path and close
                await MainActor.run {
                    UserDefaults.standard.set(folderPath, forKey: "gitRepoPath")
                    gitManager.refresh()
                    presentationMode.wrappedValue.dismiss()
                }
                
            } catch let error as GitHubAPIError {
                switch error {
                case .conflict:
                    await showErrorMessage("Repository '\(trimmedName)' already exists on GitHub")
                case .unauthorized:
                    await showErrorMessage("GitHub authentication failed. Please reconnect.")
                case .rateLimitExceeded:
                    await showErrorMessage("GitHub rate limit exceeded. Please try again later.")
                case .networkError(let err):
                    await showErrorMessage("Network error: \(err.localizedDescription)")
                default:
                    await showErrorMessage("Failed to create repository: \(error)")
                }
            } catch {
                await showErrorMessage("Unexpected error: \(error.localizedDescription)")
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
