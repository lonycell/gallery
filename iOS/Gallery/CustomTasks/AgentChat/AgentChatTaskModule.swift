// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AgentChatTaskModule.kt

import SwiftUI
import Foundation

// MARK: - System prompt constants

internal let DEFAULT_SYSTEM_PROMPT = """
You are an AI assistant that helps users by answering questions and completing tasks using skills and tools. For EVERY new task, request, or question, you MUST execute the following steps in exact order. You MUST NOT skip any steps.

CRITICAL RULE: You MUST execute all steps silently. Do NOT generate or output any internal thoughts, reasoning, explanations, or intermediate text at ANY step.

1. EVALUATE AND ROUTE:
   Determine if the request should be handled by a "Skill" (requires loading instructions) or directly by an "MCP Tool".
   - If it is a Skill: Go to Step 2.
   - If it is an MCP Tool: Go to Step 4.
   - If nothing is found, output "No skills or tools found" and stop.

--- SKILLS ---
___SKILLS___

--- MCP TOOLS ---
___TOOLS___

==================================================
FLOW A: SKILL EXECUTION
==================================================

2. Find the most relevant skill from the --- SKILLS --- list. You MUST NOT use `run_intent` or `runMcpTool` under any circumstances at this step.

3. Use the `load_skill` tool to read its instructions. Follow the skill's instructions exactly to complete the task.
   - You MUST NOT output any intermediate thoughts or status updates. No exceptions!
   - Output ONLY the final result when successful. It should contain a one-sentence summary of the action taken and the final result of the skill.
   - Stop here once Flow A is complete.

==================================================
FLOW B: MCP TOOL DIRECT EXECUTION
==================================================

4. Find the most relevant tool from the --- MCP TOOLS --- list.

5. Call the `runMcpTool` tool with the following parameters:
   - `toolName`: The name of the tool to run. Use the exact name from the list above. Do not hallucinate the name. Pay attention to casing and plurals.
   - `input`: The input JSON object that matches the tool's expected input schema.

6. Output ONLY the final result returned by the tool. You MUST NOT output any intermediate thoughts or status updates. No exceptions!
"""

internal let DEFAULT_SYSTEM_PROMPT_SKILLS_ONLY = """
You are an AI assistant that helps users by answering questions and completes tasks using skills. For EVERY new task or request or question, you MUST execute the following steps in exact order. You MUST NOT skip any steps.

CRITICAL RULE: You MUST execute all steps silently. Do NOT generate or output any internal thoughts, reasoning, explanations, or intermediate text at ANY step.

1. First, find the most relevant skill from the following list:

___SKILLS___

After this step you MUST go to next step. You MUST NOT use `run_intent` under any circumstances at this step.

2. If a relevant skill exists, use the `load_skill` tool to read its instructions. You MUST NOT use `run_intent` under any circumstances at this step.

3. Follow the skill's instructions exactly to complete the task. You MUST NOT output any intermediate thoughts or status updates. No exceptions! Output ONLY the final result when successful. It should contain one-sentence summary of the action taken, and the final result of the skill.

4. If no relevant skill is found, output "No relevant skills found" and stop.
"""

// MARK: - Helpers

/// Checks whether the system prompt is the default (unmodified) one.
func isDefaultSystemPrompt(_ prompt: String) -> Bool {
    let t1 = DEFAULT_SYSTEM_PROMPT.trimmingCharacters(in: .whitespacesAndNewlines)
    let t2 = DEFAULT_SYSTEM_PROMPT_SKILLS_ONLY.trimmingCharacters(in: .whitespacesAndNewlines)
    let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return p == t1 || p == t2
}

/// Returns the correct base system prompt depending on whether MCP tools are present.
func getEffectiveBaseSystemPrompt(currentPrompt: String, hasMcpTools: Bool) -> String {
    if isDefaultSystemPrompt(currentPrompt) {
        return hasMcpTools
            ? DEFAULT_SYSTEM_PROMPT.trimmingCharacters(in: .whitespacesAndNewlines)
            : DEFAULT_SYSTEM_PROMPT_SKILLS_ONLY.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return currentPrompt
}

/// Injects skill names/descriptions and MCP tool prompt into the system prompt placeholders.
func injectSkillsAndMcpTools(baseSystemPrompt: String, skills: [Skill], toolsPrompt: String) -> String {
    let skillsText = skills.filter { $0.selected }
        .map { "- Skill name: \"\($0.name)\"\n- Description: \($0.description)" }
        .joined(separator: "\n\n")

    if skillsText.isEmpty && toolsPrompt.isEmpty { return "" }
    return baseSystemPrompt
        .replacingOccurrences(of: "___SKILLS___", with: skillsText)
        .replacingOccurrences(of: "___TOOLS___", with: toolsPrompt)
}

// MARK: - AgentChatTask (CustomTask)

final class AgentChatTask: CustomTask {
    let task: Task
    private let agentTools = AgentTools()

    init() {
        task = Task(
            id: BuiltInTaskId.LLM_AGENT_CHAT,
            label: "Agent Skills",
            category: CategoryInfo(id: "llm", title: Str.categoryLlm),
            icon: .system("cpu"),
            iconVectorAssetName: "agent",
            description: "Chat with on-device large language models with skills and tools",
            shortDescription: "Complete agentic tasks with chat",
            docUrl: "https://github.com/google-ai-edge/LiteRT-LM/blob/main/kotlin/README.md",
            sourceCodeUrl: "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/agentchat/",
            models: [],
            modelNames: [],
            handleModelConfigChangesInTask: false,
            experimental: false,
            newFeature: true,
            useThemeColor: false,
            defaultSystemPrompt: DEFAULT_SYSTEM_PROMPT.trimmingCharacters(in: .whitespacesAndNewlines),
            agentName: Str.chatAgentAgentName,
            textInputPlaceHolder: Str.chatTextinputPlaceholder
        )
    }

    func initializeModelFn(model: Model, systemInstruction: Contents?, onDone: @escaping (String) -> Void) {
        // NOTE: The real initialization (loading skills, MCP servers, then calling LlmChatModelHelper.initialize
        // with tool=[agentTools]) happens on the AgentChatScreen side where we have access to the view models.
        // Here we just forward to LlmModelHelper.
        Task {
            // Stub: actual LiteRT-LM init not implemented on iOS — see LlmModelHelper.swift.
            onDone("")
        }
    }

    func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
        Task { onDone() }
    }

    /// The DataStoreRepository must be injected by the caller (GalleryNavGraph / integrator)
    /// before `mainScreen` is called. It is set via `setDataStoreRepository(_:)`.
    var dataStoreRepository: DataStoreRepository?

    func setDataStoreRepository(_ repo: DataStoreRepository) {
        self.dataStoreRepository = repo
    }

    @MainActor func mainScreen(data: Any) -> AnyView {
        guard let builtin = data as? CustomTaskDataForBuiltinTask else {
            return AnyView(Text("Invalid data for AgentChatTask"))
        }
        // NOTE: The DataStoreRepository must be set by the integrator before calling mainScreen.
        // In GalleryNavGraph, call `(task as? AgentChatTask)?.setDataStoreRepository(appContainer.dataStoreRepository)`
        // after obtaining the task from ModelManagerViewModel.getCustomTaskByTaskId(BuiltInTaskId.LLM_AGENT_CHAT).
        guard let repo = dataStoreRepository else {
            return AnyView(Text("AgentChatTask: DataStoreRepository not configured."))
        }
        return AnyView(
            AgentChatScreen(
                task: task,
                modelManagerViewModel: builtin.modelManagerViewModel,
                navigateUp: builtin.onNavUp,
                agentTools: agentTools,
                dataStoreRepository: repo,
                initialQuery: builtin.initialQuery
            )
        )
    }
}

// MARK: - AgentChatTaskModule (factory)

enum AgentChatTaskModule {
    /// Factory called by the integrator in `BuiltInTasks.makeAll()` or `FeatureTaskModules.registered()`.
    static func make() -> CustomTask { AgentChatTask() }
}
