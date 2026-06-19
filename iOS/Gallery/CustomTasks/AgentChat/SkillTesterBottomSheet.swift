// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/SkillTesterBottomSheet.kt

import SwiftUI

/// A bottom sheet for testing a JS skill interactively.
struct SkillTesterBottomSheet: View {
    @ObservedObject var agentTools: AgentTools
    let skill: Skill
    let onDismiss: () -> Void

    @State private var inputData = ""
    @State private var result = ""
    @State private var error = ""
    @State private var logs = ""
    @State private var selectedTabIndex = 0
    @State private var running = false
    @State private var resultImage: UIImage?
    @State private var resultWebviewURL: String?

    @Environment(\.galleryColors) var colors

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(skill.name).font(AppTypography.titleLarge).padding(.horizontal, 16).padding(.top, 16)

                // Input fields
                VStack(spacing: 8) {
                    TextField("Input Data", text: $inputData, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                }
                .padding(.horizontal, 16).padding(.top, 8)

                // Tabs
                Picker("", selection: $selectedTabIndex) {
                    Text("Result").tag(0)
                    Text("Logs").tag(1)
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)

                // Tab content
                ScrollView {
                    if selectedTabIndex == 0 {
                        resultContent
                    } else {
                        Text(logs).font(.system(size: 12, design: .monospaced)).padding(16)
                    }
                }

                // Run button
                Button(action: runSkill) {
                    Text(running ? "Running…" : "Run").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            let displayText = error.isEmpty ? result : error
            if !displayText.isEmpty {
                Text(displayText)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(error.isEmpty ? colors.onSurface : colors.error)
                    .padding(16)
            }
            if let img = resultImage {
                Image(uiImage: img).resizable().scaledToFit().padding(.horizontal, 16)
            }
            if let url = resultWebviewURL, let u = URL(string: url) {
                Link("Open in browser: \(url)", destination: u)
                    .font(AppTypography.bodySmall).padding(.horizontal, 16)
            }
        }
    }

    private func runSkill() {
        running = true
        result = ""; error = ""; resultImage = nil; resultWebviewURL = nil
        _Concurrency.Task {
            guard let url = agentTools.skillManagerViewModel.getJsSkillUrl(skillName: skill.name, scriptName: DEFAULT_SCRIPT_NAME) else {
                await MainActor.run { error = "JS skill URL not specified"; running = false }
                return
            }
            let action = CallJsAgentAction(url: url, data: inputData)
            agentTools.sendAgentAction(action)
            let rawResult = await action.result.await()
            await MainActor.run {
                if let data = rawResult.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(CallJsSkillResult.self, from: data) {
                    result = "{\"result\": \"\(parsed.result ?? "")\", \"error\": \"\(parsed.error ?? "")\"}"
                    if let b64 = parsed.image?.base64 {
                        let pure = b64.components(separatedBy: ",").last ?? b64
                        if let d = Data(base64Encoded: pure), let img = UIImage(data: d) { resultImage = img }
                    }
                    if let wv = parsed.webview { resultWebviewURL = wv.url }
                } else {
                    result = rawResult
                }
                running = false
            }
        }
    }
}

private let DEFAULT_SCRIPT_NAME = "index.html"
