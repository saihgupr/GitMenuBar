//
//  GitHubAPIClient.swift
//  GitMenuBar
//

import Foundation

struct GitHubRepository: Codable {
    let id: Int
    let name: String
    let fullName: String
    let htmlUrl: String
    let cloneUrl: String
    let `private`: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
        case `private`
    }
}

struct GitHubUser: Codable {
    let login: String
    let id: Int
    let name: String?
}

enum GitHubAPIError: Error {
    case unauthorized
    case notFound
    case conflict
    case networkError(Error)
    case invalidResponse
    case rateLimitExceeded
    case unknown(String)
}

class GitHubAPIClient {
    private let baseURL = "https://api.github.com"
    private let authManager: GitHubAuthManager
    
    init(authManager: GitHubAuthManager) {
        self.authManager = authManager
    }
    
    // MARK: - Create Repository
    
    func createRepository(name: String, isPrivate: Bool, description: String? = nil) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        let url = URL(string: "\(baseURL)/user/repos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "name": name,
            "private": isPrivate,
            "auto_init": false  // Don't create README, we'll push our own initial commit
        ]
        
        if let description = description {
            body["description"] = description
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 201:
                // Success
                let decoder = JSONDecoder()
                let repo = try decoder.decode(GitHubRepository.self, from: data)
                return repo
            case 401:
                throw GitHubAPIError.unauthorized
            case 404:
                throw GitHubAPIError.notFound
            case 422:
                // Repository already exists
                throw GitHubAPIError.conflict
            case 429:
                throw GitHubAPIError.rateLimitExceeded
            default:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
    
    // MARK: - Check Repository Exists
    
    func checkRepositoryExists(name: String) async throws -> Bool {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        guard !authManager.username.isEmpty else {
            return false
        }
        
        let url = URL(string: "\(baseURL)/repos/\(authManager.username)/\(name)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Get Repository
    
    func getRepository(name: String) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        guard !authManager.username.isEmpty else {
            throw GitHubAPIError.unknown("Username not available")
        }
        
        return try await getRepository(owner: authManager.username, name: name)
    }

    func getRepository(owner: String, name: String) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(name)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                let repo = try decoder.decode(GitHubRepository.self, from: data)
                return repo
            case 401:
                throw GitHubAPIError.unauthorized
            case 404:
                throw GitHubAPIError.notFound
            default:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
    
    // MARK: - Check Any Repository URL Exists
    
    func checkRepositoryURLExists(owner: String, repo: String) async -> Bool {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        // Add auth if available (for private repos), but don't require it
        if let token = authManager.getStoredToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Get Current User
    
    func getCurrentUser() async throws -> GitHubUser {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        let url = URL(string: "\(baseURL)/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw GitHubAPIError.unauthorized
            }
            
            let decoder = JSONDecoder()
            let user = try decoder.decode(GitHubUser.self, from: data)
            return user
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
    
    // MARK: - Delete Repository
    
    func deleteRepository(owner: String, name: String) async throws {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 204:
                // Success - repository deleted
                return
            case 401:
                throw GitHubAPIError.unauthorized
            case 403:
                throw GitHubAPIError.unknown("Forbidden - token may not have delete_repo scope")
            case 404:
                throw GitHubAPIError.notFound
            default:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
    
    // MARK: - Update Repository Visibility
    
    func updateRepositoryVisibility(owner: String, name: String, isPrivate: Bool) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "private": isPrivate
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                // Success
                let decoder = JSONDecoder()
                let repo = try decoder.decode(GitHubRepository.self, from: data)
                return repo
            case 401:
                throw GitHubAPIError.unauthorized
            case 403:
                throw GitHubAPIError.unknown("Forbidden - token may not have repo scope")
            case 404:
                throw GitHubAPIError.notFound
            case 422:
                throw GitHubAPIError.unknown("Unprocessable Entity - validation failed")
            default:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
}
