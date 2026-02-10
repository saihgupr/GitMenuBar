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
    @Published var isAuthenticating: Bool = false
    @Published var userCode: String = ""
    @Published var authError: String = ""
    
    // Using GitHub CLI's official Client ID - no risk of account flagging!
    private let clientID = "178c6fc778ccc68e1d6a"
    private let scope = "repo delete_repo"
    
    private let keychainService = "com.pizzaman.GitMenuBar"
    private let keychainAccount = "github-access-token"
    
    // Device flow state
    private var deviceCode: String = ""
    private var pollingInterval: Int = 5
    private var pollingTimer: Timer?
    
    init() {
        // Check if we have a stored token
        if let _ = getStoredToken() {
            isAuthenticated = true
            // Fetch username in background
            Task {
                await fetchUsername()
            }
        }
    }
    
    // MARK: - Device Flow OAuth
    
    /// Start the GitHub Device Flow authentication
    func startDeviceFlow() {
        isAuthenticating = true
        authError = ""
        userCode = ""
        
        Task {
            await initiateDeviceFlow()
        }
    }
    
    /// Step 1: Request device and user codes from GitHub
    private func initiateDeviceFlow() async {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": clientID,
            "scope": scope
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error
                if let error = json["error"] as? String {
                    let errorDesc = json["error_description"] as? String ?? error
                    await MainActor.run {
                        self.authError = errorDesc
                        self.isAuthenticating = false
                    }
                    return
                }
                
                // Extract device flow data
                guard let deviceCode = json["device_code"] as? String,
                      let userCode = json["user_code"] as? String,
                      let verificationUri = json["verification_uri"] as? String,
                      let interval = json["interval"] as? Int else {
                    await MainActor.run {
                        self.authError = "Invalid response from GitHub"
                        self.isAuthenticating = false
                    }
                    return
                }
                
                self.deviceCode = deviceCode
                self.pollingInterval = interval
                
                await MainActor.run {
                    self.userCode = userCode
                    
                    // Copy code to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                }
                
                // Open browser to verification URL
                if let url = URL(string: verificationUri) {
                    _ = await MainActor.run {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                // Start polling for the token
                await startPolling()
            }
        } catch {
            await MainActor.run {
                self.authError = "Network error: \(error.localizedDescription)"
                self.isAuthenticating = false
            }
        }
    }
    
    /// Step 2: Poll GitHub for the access token until user authorizes
    private func startPolling() async {
        // Poll with the specified interval
        while isAuthenticating {
            try? await Task.sleep(nanoseconds: UInt64(pollingInterval) * 1_000_000_000)
            
            let result = await pollForToken()
            
            switch result {
            case .success(let token):
                // Store token and update state
                storeToken(token)
                await MainActor.run {
                    self.isAuthenticated = true
                    self.isAuthenticating = false
                    self.userCode = ""
                }
                await fetchUsername()
                return
                
            case .pending:
                // Keep polling
                continue
                
            case .slowDown:
                // Increase polling interval
                pollingInterval += 5
                continue
                
            case .error(let message):
                await MainActor.run {
                    self.authError = message
                    self.isAuthenticating = false
                    self.userCode = ""
                }
                return
            }
        }
    }
    
    private enum PollResult {
        case success(String)
        case pending
        case slowDown
        case error(String)
    }
    
    private func pollForToken() async -> PollResult {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for success
                if let accessToken = json["access_token"] as? String {
                    return .success(accessToken)
                }
                
                // Check for errors
                if let error = json["error"] as? String {
                    switch error {
                    case "authorization_pending":
                        return .pending
                    case "slow_down":
                        return .slowDown
                    case "expired_token":
                        return .error("Authorization expired. Please try again.")
                    case "access_denied":
                        return .error("Access denied by user.")
                    default:
                        let desc = json["error_description"] as? String ?? error
                        return .error(desc)
                    }
                }
            }
            
            return .error("Invalid response from GitHub")
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }
    
    /// Cancel the ongoing authentication
    func cancelAuthentication() {
        isAuthenticating = false
        userCode = ""
        deviceCode = ""
        authError = ""
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
}
