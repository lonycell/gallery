// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AgentTools.kt

import Foundation
import SwiftUI

// MARK: - AgentTools

/// Central toolbox bridging the LLM tool-calling loop to Skills and MCP servers.
/// Mirrors `AgentTools : ToolSet` from Android.
///
/// NOTE: Android's LiteRT-LM runtime invokes annotated `@Tool` methods via reflection.
/// On iOS there is no equivalent runtime — `AgentTools` exposes its methods as plain
/// Swift async functions that the `AgentChatViewModel` / `LlmModelHelper` call via a
/// `ToolProvider` protocol (defined in `LlmModelHelper.swift`). Wire them in when the
/// on-device inference runtime is available.
@MainActor
final class AgentTools: ObservableObject {
    // Set by AgentChatScreen before first model run.
    var skillManagerViewModel: SkillManagerViewModel!
    var mcpManagerViewModel: McpManagerViewModel!
    var taskId: String = ""

    // Channel equivalent: we use an AsyncStream backed by a continuation.
    private var actionContinuation: AsyncStream<AgentAction>.Continuation?
    let actionStream: AsyncStream<AgentAction>

    var resultImageToShow: CallJsSkillResultImage?
    var resultWebviewToShow: CallJsSkillResultWebview?

    nonisolated init() {
        var cont: AsyncStream<AgentAction>.Continuation!
        actionStream = AsyncStream { cont = $0 }
        actionContinuation = cont
    }

    func sendAgentAction(_ action: AgentAction) {
        actionContinuation?.yield(action)
    }

    func postProgress(label: String, inProgress: Bool) {
        sendAgentAction(SkillProgressAgentAction(label: label, inProgress: inProgress))
    }

    // MARK: - Tool: loadSkill

    /// Loads a skill's instructions. Mirrors `@Tool fun loadSkill(skillName)`.
    func loadSkill(skillName: String) async -> [String: String] {
        let skills = skillManagerViewModel.getSelectedSkills()
        let skill = skills.first(where: { $0.name == skillName.trimmingCharacters(in: .whitespaces) })
        let skillContent: String
        if let skill = skill {
            skillContent = "---\nname: \(skill.name)\ndescription: \(skill.description)\n---\n\n\(skill.instructions)"
            sendAgentAction(SkillProgressAgentAction(
                label: "Loading skill \"\(skillName)\"", inProgress: true,
                addItemTitle: "Load \"\(skill.name)\"",
                addItemDescription: "Description: \(skill.description)",
                customData: skill))
        } else {
            skillContent = "Skill not found"
            sendAgentAction(SkillProgressAgentAction(label: "Failed to load skill \"\(skillName)\"", inProgress: false))
        }
        return ["skill_name": skillName, "skill_instructions": skillContent]
    }

    // MARK: - Tool: runMcpTool

    /// Calls a remote MCP tool. Mirrors `@Tool fun runMcpTool(toolName, input)`.
    func runMcpTool(toolName: String, input: String) async -> [String: String] {
        let servers = mcpManagerViewModel.uiState.mcpServers
        guard let serverState = servers.first(where: { $0.mcpServer.tools.contains { $0.name == toolName } }) else {
            let skills = skillManagerViewModel.getSelectedSkills()
            let isSkill = skills.contains { $0.name == toolName.trimmingCharacters(in: .whitespaces) }
            let error = isSkill ? "Tool not found. Try to run it as a skill" : "Tool not found"
            return ["error": error, "status": "failed"]
        }
        guard let client = serverState.client else {
            return ["error": "Client not initialized", "status": "failed"]
        }

        let mcpTool = serverState.mcpServer.tools.first(where: { $0.name == toolName })
        let isAlwaysAllow = mcpTool?.alwaysAllow ?? false

        if !isAlwaysAllow {
            let permissionAction = AskMcpToolCallPermissionAction(toolName: toolName, argument: input)
            sendAgentAction(permissionAction)
            let result = await permissionAction.result.await()
            if result == .deny {
                sendAgentAction(SkillProgressAgentAction(label: "Permission denied for MCP tool \"\(toolName)\"", inProgress: false))
                return ["error": "Permission denied by user", "status": "failed"]
            }
        }

        sendAgentAction(SkillProgressAgentAction(
            label: "Calling MCP tool \"\(toolName)\"", inProgress: true,
            addItemTitle: "Call MCP tool: \"\(toolName)\"",
            addItemDescription: "- Input: \(input)"))

        do {
            // Parse input JSON string into [String: AnyCodable]
            // NOTE: We perform a best-effort decode; complex nested schemas may need fuller AnyCodable support.
            var args: [String: AnyCodable] = [:]
            if let data = input.data(using: .utf8),
               let obj = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
                args = obj
            }
            let result = try await client.callTool(name: toolName, arguments: args)
            let isError = result.isError == true
            let text = (result.content ?? []).compactMap { $0.text }.joined(separator: "\n")

            if isError {
                sendAgentAction(SkillProgressAgentAction(
                    label: "Failed to call MCP tool \"\(toolName)\"", inProgress: false,
                    addItemTitle: "Call MCP tool \"\(toolName)\" failed",
                    addItemDescription: text))
                return ["error": text, "status": "failed"]
            } else {
                sendAgentAction(SkillProgressAgentAction(
                    label: "Succeeded calling MCP tool \"\(toolName)\"", inProgress: true,
                    addItemTitle: "Call MCP tool \"\(toolName)\" succeeded",
                    addItemDescription: text))
                return ["result": text, "status": "succeeded"]
            }
        } catch {
            sendAgentAction(SkillProgressAgentAction(
                label: "Error calling MCP tool \"\(toolName)\"", inProgress: false,
                addItemTitle: "Call MCP tool \"\(toolName)\" failed",
                addItemDescription: error.localizedDescription))
            return ["error": error.localizedDescription, "status": "failed"]
        }
    }

    // MARK: - Tool: runJs

    /// Loads and executes a JS skill via WKWebView. Mirrors `@Tool fun runJs(...)`.
    func runJs(skillName: String, scriptName: String, data: String) async -> [String: Any] {
        let skills = skillManagerViewModel.getSelectedSkills()
        guard skills.contains(where: { $0.name == skillName.trimmingCharacters(in: .whitespaces) }) else {
            sendAgentAction(SkillProgressAgentAction(label: "Failed to call skill \"\(scriptName)\"", inProgress: false))
            return ["error": "Skill \"\(scriptName)\" not found", "status": "failed"]
        }
        let skill = skills.first(where: { $0.name == skillName.trimmingCharacters(in: .whitespaces) })!

        // Handle secret
        var secret = ""
        if skill.requireSecret {
            let savedSecret = skillManagerViewModel.dataStoreRepository.readSecret(key: getSkillSecretKey(skillName: skillName))
            if savedSecret == nil || savedSecret!.isEmpty {
                let action = AskInfoAgentAction(
                    dialogTitle: "Enter secret",
                    fieldLabel: skill.requireSecretDescription.isEmpty ? "The JS script needs a secret (API key / token) to proceed:" : skill.requireSecretDescription)
                sendAgentAction(action)
                secret = await action.result.await()
                if !secret.isEmpty {
                    skillManagerViewModel.dataStoreRepository.saveSecret(key: getSkillSecretKey(skillName: skillName), value: secret)
                }
            } else {
                secret = savedSecret!
            }
        }

        guard let url = skillManagerViewModel.getJsSkillUrl(skillName: skillName, scriptName: scriptName) else {
            return ["result": "JS Skill URL not set properly or skill not found"]
        }

        sendAgentAction(SkillProgressAgentAction(
            label: "Calling JS script \"\(skillName)/\(scriptName)\"", inProgress: true,
            addItemTitle: "Call JS script: \"\(skillName)/\(scriptName)\"",
            addItemDescription: "- URL: \(url.replacingOccurrences(of: LOCAL_URL_BASE, with: ""))\n- Data: \(data)",
            customData: skill))

        let action = CallJsAgentAction(url: url, data: data.trimmingCharacters(in: .whitespaces).isEmpty ? "{}" : data.trimmingCharacters(in: .whitespaces), secret: secret)
        sendAgentAction(action)
        let result = await action.result.await()

        // Parse CallJsSkillResult
        if let resultData = result.data(using: .utf8),
           let resultJson = try? JSONDecoder().decode(CallJsSkillResult.self, from: resultData) {
            if let error = resultJson.error, !error.isEmpty {
                return ["error": error, "status": "failed"]
            }
            if let image = resultJson.image { resultImageToShow = image }
            if let webview = resultJson.webview {
                let webviewUrl = skillManagerViewModel.getJsSkillWebviewUrl(skillName: skillName, url: webview.url ?? "")
                resultWebviewToShow = CallJsSkillResultWebview(url: webviewUrl, iframe: webview.iframe, aspectRatio: webview.aspectRatio)
            }
            return ["result": resultJson.result ?? "", "status": "succeeded"]
        }
        // Unparseable — treat the whole string as result
        return ["result": result, "status": "succeeded"]
    }

    // MARK: - Tool: runIntent

    /// Runs a native intent/action. Mirrors `@Tool fun runIntent(...)`.
    func runIntent(intent: String, parameters: String) async -> [String: String] {
        guard IntentAction.from(intent) != nil else {
            let skills = skillManagerViewModel.getSelectedSkills()
            let isSkill = skills.contains { $0.name == intent.trimmingCharacters(in: .whitespaces) }
            let error = isSkill ? "Intent not found. Try to run it as a skill" : "Tool not found"
            return ["error": error, "status": "failed"]
        }
        sendAgentAction(SkillProgressAgentAction(
            label: "Executing intent \"\(intent)\"", inProgress: true,
            addItemTitle: "Execute intent \"\(intent)\"",
            addItemDescription: "Parameters: \(parameters)"))

        let res = await IntentHandler.handleAction(action: intent, parameters: parameters) { permission in
            let permAction = RequestPermissionAgentAction(permission: permission)
            self.sendAgentAction(permAction)
            return await permAction.result.await()
        }
        return ["action": intent, "parameters": parameters, "result": res]
    }
}
