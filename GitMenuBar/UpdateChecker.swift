//
//  UpdateChecker.swift
//  GitMenuBar
//

import Foundation
import AppKit

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let owner = "saihgupr"
    private let repo = "GitMenuBar"

    private var lastCheckDate: Date?

    private init() {}

    func checkForUpdatesOnLaunch() {
        Task { @MainActor in
            do {
                if let update = try await fetchUpdateIfAvailable() {
                    presentUpdateAlert(update: update)
                }
            } catch {
                // Silent failure on launch; don't interrupt user experience.
            }
        }
    }

    private func fetchUpdateIfAvailable() async throws -> GitHubRelease? {
        if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < 60 {
            return nil
        }

        lastCheckDate = Date()

        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if isVersion(latestVersion, greaterThan: currentVersion) {
            return release
        }

        return nil
    }

    private func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }

        let maxCount = max(lhsParts.count, rhsParts.count)
        for i in 0..<maxCount {
            let lhsValue = i < lhsParts.count ? lhsParts[i] : 0
            let rhsValue = i < rhsParts.count ? rhsParts[i] : 0

            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
        }

        return false
    }

    @MainActor
    private func presentUpdateAlert(update: GitHubRelease) {
        let latestVersion = update.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Available"
        alert.informativeText = "A newer version (v\(latestVersion)) is available. Would you like to open the download page?"
        alert.addButton(withTitle: "Open Downloads")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: update.htmlUrl) {
            NSWorkspace.shared.open(url)
        }
    }
}
