//
//  GitHubAuthManager.swift
//  GitMenuBar
//

import Foundation
import Security
import AppKit

class GitHubAuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var username: String = ""
    
    // GitHub OAuth App credentials
    private let clientID = "Ov23li18AAshWi4ZEiCm"
    private let clientSecret = "2d875ff8f1a8a1a8ec30db58e17398ce4bd25f02"
    private let redirectURI = "gitmenubar://oauth/callback"
    private let scope = "repo" // Allows creating public and private repos
    
    private let keychainService = "com.pizzaman.GitMenuBar"
    private let keychainAccount = "github-access-token"
    
    init() {
        // Check if we have a stored token
        if let token = getStoredToken() {
            isAuthenticated = true
            // Fetch username in background
            Task {
                await fetchUsername()
            }
        }
    }
    
    // MARK: - OAuth Flow
    
    func startOAuthFlow() {
        let authURL = "https://github.com/login/oauth/authorize"
        let params = [
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "scope": scope,
            "state": generateState() // Random string for security
        ]
        
        var components = URLComponents(string: authURL)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
    
    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("Invalid callback URL")
            return
        }
        
        // Extract code from callback
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            print("No code in callback")
            return
        }
        
        // Exchange code for access token
        Task {
            await exchangeCodeForToken(code: code)
        }
    }
    
    // MARK: - Token Exchange
    
    private func exchangeCodeForToken(code: String) async {
        let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURI
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                // Store token securely
                storeToken(accessToken)
                
                // Update state
                await MainActor.run {
                    self.isAuthenticated = true
                }
                
                // Fetch username
                await fetchUsername()
            } else {
                print("Failed to get access token")
            }
        } catch {
            print("Error exchanging code for token: \(error)")
        }
    }
    
    // MARK: - Token Storage (Keychain)
    
    private func storeToken(_ token: String) {
        let data = token.data(using: .utf8)!
        
        // Delete existing token first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new token
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error storing token in keychain: \(status)")
        }
    }
    
    func getStoredToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    private func deleteStoredToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - User Info
    
    private func fetchUsername() async {
        guard let token = getStoredToken() else { return }
        
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let login = json["login"] as? String {
                await MainActor.run {
                    self.username = login
                }
            }
        } catch {
            print("Error fetching username: \(error)")
        }
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        deleteStoredToken()
        isAuthenticated = false
        username = ""
    }
    
    // MARK: - Helpers
    
    private func generateState() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in letters.randomElement()! })
    }
}
