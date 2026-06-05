// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AddOrEditSkillBottomSheet.kt

import SwiftUI

private let DEFAULT_SCRIPT_NAME = "index.html"
private let CALL_JS_INSTRUCTIONS_TEMPLATE = """
# Instructions

Call the `run_js` tool with the following exact parameters:

- data: A JSON string with the following fields:
  - [fieldName]: [Data type, e.g. String, Number, Array] - [short description].
  - ...
"""

struct AddOrEditSkillBottomSheet: View {
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    let skillIndex: Int
    let onDismiss: () -> Void
    let onSuccess: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var selectedTabIndex = 0
    @State private var scriptContents: [String: String] = [:]
    @State private var selectedScript: String?
    @State private var scriptsLoading = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showDiscardAlert = false
    @State private var edited = false
    @State private var showAddScriptAlert = false
    @State private var newScriptName = ""
    @State private var showDeleteScriptAlert = false
    @State private var showGeneratePromptSheet = false
    @State private var llmRequirements = ""
    @State private var llmInputData = "- [fieldName]: [Data type (String, Number, Array)] - [short description]"
    @State private var llmOutputData = "- [fieldName]: [Data type (String, Number, Array)] - [short description]"

    @Environment(\.galleryColors) var colors
    @Environment(\.customColors) var customColors

    private var uiState: SkillManagerUiState { skillManagerViewModel.uiState }
    private var skill: Skill? { uiState.skills.first(where: { uiState.skills.firstIndex(of: $0) == skillIndex })?.skill }
    private var isViewing: Bool { true }  // Read-only view like Android's viewingMode = true
    private var isNew: Bool { skillIndex < 0 || skillIndex >= uiState.skills.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title
                let titleText = isViewing ? "View skill: \(skill?.name ?? "")" :
                    (!isNew ? "Edit skill: \(skill?.name ?? "")" : Str.addSkillManualInputSheetTitle)
                Text(titleText).font(AppTypography.titleLarge).padding(.horizontal, 16).padding(.top, 16)

                // Tab bar (only in edit mode)
                if !isViewing {
                    Picker("", selection: $selectedTabIndex) {
                        Text("Info").tag(0)
                        Text("Scripts").tag(1)
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 8)
                } else {
                    Spacer().frame(height: 8)
                }

                // Content
                ScrollView {
                    if selectedTabIndex == 0 {
                        infoTab
                    } else {
                        scriptsTab
                    }
                }

                // Action buttons
                HStack {
                    Spacer()
                    if isViewing {
                        Button(Str.ok) { onDismiss() }.buttonStyle(.borderedProminent)
                    } else {
                        Button(Str.cancel) {
                            if edited { showDiscardAlert = true }
                            else { onDismiss() }
                        }.buttonStyle(.bordered)
                        Button(Str.save) {
                            skillManagerViewModel.saveSkillEdit(
                                index: skillIndex, name: name, description: description,
                                instructions: instructions, scriptsContent: scriptContents,
                                onSuccess: { onDismiss(); onSuccess() },
                                onError: { errorMessage = $0; showErrorAlert = true })
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty || description.isEmpty || !edited)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(colors.surfaceContainer)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            if let s = skill {
                name = s.name; description = s.description; instructions = s.instructions
                llmRequirements = s.description
                scriptsLoading = true
                skillManagerViewModel.loadSkillScriptsContent(skill: s) { loaded in
                    Task { @MainActor in
                        scriptContents = loaded
                        selectedScript = loaded.keys.first(where: { $0 == DEFAULT_SCRIPT_NAME }) ?? loaded.keys.first
                        scriptsLoading = false
                    }
                }
            }
        }
        .alert(Str.failedToSave, isPresented: $showErrorAlert) {
            Button(Str.ok) { showErrorAlert = false }
        } message: { Text(errorMessage) }
        .alert(Str.discardChangesDialogTitle, isPresented: $showDiscardAlert) {
            Button(Str.cancel, role: .cancel) { showDiscardAlert = false }
            Button(Str.discard, role: .destructive) { onDismiss() }
        } message: { Text(Str.discardChangesDialogContent) }
        .sheet(isPresented: $showGeneratePromptSheet) {
            GenerateLlmPromptBottomSheet(
                curDescription: description, requirements: $llmRequirements,
                inputData: $llmInputData, outputData: $llmOutputData,
                onDismiss: { showGeneratePromptSheet = false },
                onGenerated: { _ in showGeneratePromptSheet = false })
        }
    }

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text(Str.name).font(AppTypography.labelMedium)
                TextField("", text: $name).textFieldStyle(.roundedBorder).disabled(isViewing)
                    .onChange(of: name) { _ in edited = true }
                Text(Str.skillNameInputDescription).font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant)
            }
            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text(Str.descriptionRequired).font(AppTypography.labelMedium)
                TextField("", text: $description, axis: .vertical).textFieldStyle(.roundedBorder)
                    .lineLimit(3...6).disabled(isViewing).onChange(of: description) { _ in edited = true }
                Text(Str.skillDescriptionInputDescription).font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant)
            }
            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                if !isViewing {
                    HStack {
                        Spacer()
                        Button(action: { instructions = CALL_JS_INSTRUCTIONS_TEMPLATE; edited = true }) {
                            Label(Str.useCallJsTemplate, systemImage: "list.bullet.rectangle")
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Text(Str.instructions).font(AppTypography.labelMedium)
                TextField("", text: $instructions, axis: .vertical).textFieldStyle(.roundedBorder)
                    .lineLimit(6...20).font(.system(size: 13)).disabled(isViewing)
                    .onChange(of: instructions) { _ in edited = true }
                Text(Str.skillInstructionsInputDescription).font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant)
            }
        }
        .padding(16)
    }

    private var scriptsTab: some View {
        Group {
            if scriptsLoading {
                ProgressView().padding(.top, 40)
            } else if scriptContents.isEmpty {
                VStack {
                    Spacer().frame(height: 40)
                    Button(Str.addDefaultScript) {
                        scriptContents[DEFAULT_SCRIPT_NAME] = ""; selectedScript = DEFAULT_SCRIPT_NAME; edited = true
                    }.buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // Script picker + add/delete
                    HStack {
                        Picker("", selection: Binding(get: { selectedScript ?? "" }, set: { selectedScript = $0 })) {
                            ForEach(scriptContents.keys.sorted(), id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).frame(maxWidth: .infinity)
                        Button(action: { showAddScriptAlert = true }) { Image(systemName: "plus") }
                        Button(action: { showDeleteScriptAlert = true }) { Image(systemName: "trash") }
                    }

                    // Prompt helper buttons
                    HStack(spacing: 8) {
                        Button(action: { showGeneratePromptSheet = true }) {
                            Label(Str.generateLlmPromptButtonLabel, systemImage: "sparkles")
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                        Button(action: {
                            if let clip = UIPasteboard.general.string, let script = selectedScript {
                                scriptContents[script] = clip; edited = true
                            }
                        }) {
                            Label(Str.pasteFromClipboard, systemImage: "doc.on.clipboard")
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                    }

                    // Code editor
                    if let script = selectedScript {
                        TextEditor(text: Binding(get: { scriptContents[script] ?? "" }, set: { scriptContents[script] = $0; edited = true }))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 300)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.outline, lineWidth: 1))
                    }
                }
                .padding(16)
                .alert(Str.addScript, isPresented: $showAddScriptAlert) {
                    TextField(Str.scriptName, text: $newScriptName)
                    Button(Str.cancel, role: .cancel) { newScriptName = "" }
                    Button(Str.add) {
                        let n = newScriptName.trimmingCharacters(in: .whitespaces)
                        scriptContents[n] = ""; selectedScript = n; edited = true; newScriptName = ""
                    }.disabled(newScriptName.isEmpty || scriptContents.keys.contains(newScriptName))
                }
                .alert(Str.deleteScriptDialogTitle, isPresented: $showDeleteScriptAlert) {
                    Button(Str.cancel, role: .cancel) { }
                    Button(Str.delete, role: .destructive) {
                        if let s = selectedScript {
                            scriptContents.removeValue(forKey: s)
                            selectedScript = scriptContents.keys.first
                            if let curSkill = skill { skillManagerViewModel.deleteSkillScript(skill: curSkill, scriptName: s) }
                            edited = true
                        }
                    }
                } message: { Text("Are you sure you want to delete '\(selectedScript ?? "")'?") }
            }
        }
    }
}

private extension Str {
    static let addSkillManualInputSheetTitle = "Create a skill"
    static let name = "Name"
    static let skillNameInputDescription = "REQUIRED. In the form of my-skill-name"
    static let descriptionRequired = "Description*"
    static let skillDescriptionInputDescription = "REQUIRED. A brief description of the skill's function and trigger conditions or keywords."
    static let instructions = "Instructions"
    static let skillInstructionsInputDescription = "Detailed instructions in Markdown format that LLM must follow to accomplish the task."
    static let useCallJsTemplate = "Use call-JS template"
    static let addDefaultScript = "Add default script"
    static let generateLlmPromptButtonLabel = "Generate LLM prompt"
    static let pasteFromClipboard = "Paste from clipboard"
    static let addScript = "Add script"
    static let scriptName = "Script name"
    static let deleteScriptDialogTitle = "Delete script"
    static let failedToSave = "Failed to save"
    static let save = "Save"
    static let discard = "Discard"
    static let discardChangesDialogTitle = "Discard changes?"
    static let discardChangesDialogContent = "You have unsaved changes. Are you sure you want to discard them?"
    static let ok = "OK"
    static let cancel = "Cancel"
    static let delete = "Delete"
    static let add = "Add"
}
