// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AgentChatScreen.kt

import SwiftUI
import WebKit
import Combine

// MARK: - AgentChatScreen

/// The main screen for the Agent Chat / Skills feature.
/// Embeds the existing `ChatView` (LlmChatScreen equivalent) and layers skill/MCP overlays.
///
/// NOTE: Android's version was built on top of `LlmChatScreen` which itself contains
/// a composable tree managing chat messages, the text input panel, and toolbar buttons
/// for skills/MCP. On iOS we embed the foundation `ChatView` (which already accepts
/// `skillCount`/`mcpCount` in its `ChatPanel`) and add our additional overlays via
/// `.sheet` and `.alert` modifiers.
struct AgentChatScreen: View {
    let task: Task
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    let navigateUp: () -> Void
    @ObservedObject var agentTools: AgentTools
    @StateObject private var viewModel: AgentChatViewModel
    @StateObject private var skillManagerViewModel: SkillManagerViewModel
    @StateObject private var mcpManagerViewModel: McpManagerViewModel

    let initialQuery: String?

    @Environment(\.galleryColors) var colors
    @Environment(\.customColors) var customColors

    init(task: Task, modelManagerViewModel: ModelManagerViewModel, navigateUp: @escaping () -> Void,
         agentTools: AgentTools, dataStoreRepository: DataStoreRepository, initialQuery: String? = nil) {
        self.task = task
        self.modelManagerViewModel = modelManagerViewModel
        self.navigateUp = navigateUp
        self.agentTools = agentTools
        self.initialQuery = initialQuery
        _viewModel = StateObject(wrappedValue: AgentChatViewModel(dataStoreRepository: dataStoreRepository))
        _skillManagerViewModel = StateObject(wrappedValue: SkillManagerViewModel(dataStoreRepository: dataStoreRepository))
        _mcpManagerViewModel = StateObject(wrappedValue: McpManagerViewModel(dataStoreRepository: dataStoreRepository))
    }

    // MARK: Sheet / dialog state
    @State private var showSkillManager = false
    @State private var showMcpManager = false
    @State private var showAskInfoDialog = false
    @State private var currentAskInfoAction: AskInfoAgentAction?
    @State private var askInfoInputValue = ""
    @State private var currentMcpPermissionAction: AskMcpToolCallPermissionAction?
    @State private var showAlertForDisabledSkill = false
    @State private var disabledSkillName = ""
    @State private var curSystemPrompt = ""
    @State private var initialQueryConsumed = false

    // WKWebView reference for JS execution
    @State private var webViewRef: WKWebView?

    var body: some View {
        let skillCount = skillManagerViewModel.uiState.skills.filter { $0.skill.selected }.count
        let mcpCount = skillManagerViewModel.uiState.skills.count  // placeholder
        let mcpToolsCount = mcpManagerViewModel.uiState.mcpServers
            .filter { $0.mcpServer.enabled }
            .flatMap { $0.mcpServer.tools }
            .filter { $0.enabled }
            .count

        // Wire agentTools references
        let _ = { agentTools.skillManagerViewModel = skillManagerViewModel
                   agentTools.mcpManagerViewModel = mcpManagerViewModel
                   agentTools.taskId = task.id }()

        ZStack {
            ChatView(
                task: task,
                modelManagerViewModel: modelManagerViewModel,
                viewModel: viewModel,
                navigateUp: navigateUp,
                skillCount: skillCount,
                mcpToolsCount: mcpToolsCount,
                onSkillClicked: { showSkillManager = true },
                onMcpClicked: { showMcpManager = true },
                curSystemPrompt: curSystemPrompt,
                onSystemPromptChanged: { newPrompt in
                    curSystemPrompt = newPrompt
                    viewModel.applySystemPromptChange(
                        task: task,
                        model: modelManagerViewModel.uiState.selectedModel,
                        newPrompt: newPrompt)
                },
                getActiveSkills: {
                    skillManagerViewModel.getSelectedSkills().map { skillManagerViewModel.getSkillShortId($0) }
                },
                onResetSession: { task, model, initialMsgs, clearHistory, onDone in
                    resetSessionWithCurrentSkillsAndMcps(
                        model: model, initialMessages: initialMsgs, clearHistory: clearHistory, onDone: onDone)
                },
                emptyStateView: AnyView(emptyStateView),
                belowMessageListView: AnyView(belowMessageListView)
            )
        }
        .task {
            await skillManagerViewModel.loadSkills()
            await mcpManagerViewModel.loadMcpServers()
            // Determine initial system prompt
            let toolsPrompt = mcpManagerViewModel.getToolsPrompt()
            curSystemPrompt = getEffectiveBaseSystemPrompt(currentPrompt: task.defaultSystemPrompt, hasMcpTools: !toolsPrompt.isEmpty)
        }
        .onChange(of: mcpToolsCount) { _ in
            curSystemPrompt = getEffectiveBaseSystemPrompt(currentPrompt: curSystemPrompt, hasMcpTools: mcpToolsCount > 0)
        }
        .sheet(isPresented: $showSkillManager) {
            SkillManagerBottomSheet(
                agentTools: agentTools,
                skillManagerViewModel: skillManagerViewModel,
                onDismiss: { changed in
                    showSkillManager = false
                    if changed { resetSessionWithCurrentSkillsAndMcps() }
                })
        }
        .sheet(isPresented: $showMcpManager) {
            McpManagerBottomSheet(
                mcpManagerViewModel: mcpManagerViewModel,
                onDismiss: { changed in
                    showMcpManager = false
                    if changed { resetSessionWithCurrentSkillsAndMcps() }
                })
        }
        // AskInfo dialog (secret entry)
        .sheet(isPresented: $showAskInfoDialog) {
            if let action = currentAskInfoAction {
                SecretEditorDialog(
                    title: action.dialogTitle,
                    fieldLabel: action.fieldLabel,
                    value: $askInfoInputValue,
                    onDone: {
                        action.result.complete(askInfoInputValue)
                        showAskInfoDialog = false; currentAskInfoAction = nil
                    },
                    onDismiss: {
                        action.result.complete("")
                        showAskInfoDialog = false; currentAskInfoAction = nil
                    })
            }
        }
        // MCP permission dialog
        .sheet(item: $currentMcpPermissionAction) { action in
            McpToolCallPermissionDialog(toolName: action.toolName, argument: action.argument) { result in
                action.result.complete(result)
                if result == .alwaysAllow {
                    if let url = mcpManagerViewModel.uiState.mcpServers.first(where: { state in
                        state.mcpServer.tools.contains { $0.name == action.toolName }
                    })?.mcpServer.url {
                        mcpManagerViewModel.setMcpToolAlwaysAllow(url: url, toolName: action.toolName, alwaysAllow: true)
                    }
                }
                currentMcpPermissionAction = nil
            }
        }
        // Disabled-skill alert
        .alert("The \"\(disabledSkillName)\" skill is currently disabled", isPresented: $showAlertForDisabledSkill) {
            Button(Str.ok) { showAlertForDisabledSkill = false }
        } message: {
            Text(Str.enableSkillDialogContent)
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Text(Str.introducing)
                    .font(AppTypography.headlineSmall)
                Text(Str.agentSkills)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x85B1F8), Color(hex: 0x3174F1)], startPoint: .leading, endPoint: .trailing))
                    .padding(.vertical, 4)
                Text("Use specialized, high-order reasoning by loading different skills or creating your own. Explore community contributed skills on GitHub discussions.\n\nTry tapping a sample prompt below to see Agent Skills in action!")
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 48)
            Spacer()

            // Try-out chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TRYOUT_CHIPS, id: \.skillName) { chip in
                        if chip.skillName == "learn-something-new" &&
                            modelManagerViewModel.uiState.selectedModel.name != "Gemma-4-E4B-it" {
                            EmptyView()
                        } else {
                            Button(action: {
                                if skillManagerViewModel.isSkillSelected(skillName: chip.skillName) {
                                    // Trigger send — viewModel exposes a sendMessageTrigger
                                    viewModel.queueInitialQuery(chip.prompt)
                                } else {
                                    disabledSkillName = chip.skillName
                                    showAlertForDisabledSkill = true
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: chip.icon).frame(width: 20, height: 20)
                                    Text(chip.label)
                                }
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(colors.secondaryContainer)
                            .foregroundColor(colors.onSecondaryContainer)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Hidden WebView for JS skill execution

    private var belowMessageListView: some View {
        SkillWebViewBridge(
            agentTools: agentTools,
            skillManagerViewModel: skillManagerViewModel,
            viewModel: viewModel,
            taskId: task.id,
            onAskInfo: { action in
                currentAskInfoAction = action
                askInfoInputValue = ""
                showAskInfoDialog = true
            },
            onMcpPermission: { action in
                currentMcpPermissionAction = action
            }
        )
        .frame(width: 1, height: 1)
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - Session reset

    private func resetSessionWithCurrentSkillsAndMcps(model: Model? = nil, initialMessages: [ChatMessage] = [], clearHistory: Bool = true, onDone: (() -> Void)? = nil) {
        let selectedModel = model ?? modelManagerViewModel.uiState.selectedModel
        let toolsPrompt = mcpManagerViewModel.getToolsPrompt()
        let systemPrompt = getEffectiveBaseSystemPrompt(currentPrompt: curSystemPrompt, hasMcpTools: !toolsPrompt.isEmpty)
        let systemInstruction = injectSkillsAndMcpTools(
            baseSystemPrompt: systemPrompt,
            skills: skillManagerViewModel.getSelectedSkills(),
            toolsPrompt: toolsPrompt)
        viewModel.resetSession(
            task: task, model: selectedModel,
            systemInstruction: systemInstruction,
            clearHistory: clearHistory,
            initialMessages: initialMessages,
            onDone: { onDone?() })
    }
}

// MARK: - AskMcpToolCallPermissionAction: Identifiable (for .sheet(item:))
extension AskMcpToolCallPermissionAction: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}

// MARK: - Color(hex:) convenience
extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
