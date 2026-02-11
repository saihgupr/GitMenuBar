//
//  SettingsView.swift
//  GitMenuBar
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var repoPath = ""
    @State private var showingFilePicker = false
    @AppStorage("gitRepoPath") private var storedRepoPath = ""


    var body: some View {
        VStack(spacing: 20) {
            Text("GitBar Settings")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Git Repository Path")
                    .font(.headline)

                HStack {
                    TextField("Select repository directory", text: Binding(
                        get: { repoPath.isEmpty ? storedRepoPath : repoPath },
                        set: { repoPath = $0 }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Browse...") {
                        selectDirectory()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack {
                Button("Cancel") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    storedRepoPath = repoPath
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .frame(width: 500, height: 180)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        panel.begin { result in
            if result == .OK, let url = panel.url {
                repoPath = url.path
            }
        }
    }

}

#Preview {
    SettingsView()
}

