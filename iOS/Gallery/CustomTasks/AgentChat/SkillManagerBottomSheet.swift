// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/SkillManagerBottomSheet.kt

import SwiftUI

// MARK: - SkillManagerBottomSheet

struct SkillManagerBottomSheet: View {
    @ObservedObject var agentTools: AgentTools
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    let onDismiss: (Bool) -> Void  // Bool = selectedSkillsChanged

    @State private var searchQuery = ""
    @State private var showAddSkillOptions = false
    @State private var showAddFromUrl = false
    @State private var showAddFromLocal = false
    @State private var showAddFeatured = false
    @State private var showCommunitySkills = false
    @State private var showAddOrEdit = false
    @State private var showDeleteAlert = false
    @State private var showSecretEditor = false
    @State private var showDisclaimerSheet = false
    @State private var skillToDeleteName = ""
    @State private var skillToEditIndex = -1
    @State private var isBuiltInExpanded = false
    @State private var isCustomExpanded = true
    @State private var inMultiSelectMode = false
    @State private var selectedCustomSkillNames: Set<String> = []
    @State private var hasDeterminedExpansion = false
    @State private var savedNamesAndDescriptions = ""
    @State private var showSkillLimitBanner = false
    @State private var pendingLocalImportOption = false

    @Environment(\.galleryColors) var colors
    @Environment(\.customColors) var customColors
    @Environment(\.openURL) var openURL

    private var uiState: SkillManagerUiState { skillManagerViewModel.uiState }

    private var filteredSkills: [SkillState] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return uiState.skills }
        return uiState.skills.filter {
            $0.skill.name.lowercased().contains(q) || $0.skill.description.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if uiState.loading {
                        ProgressView().padding(.top, 60)
                        Spacer()
                    } else {
                        // Header
                        if inMultiSelectMode {
                            multiSelectHeader
                        } else {
                            normalHeader
                        }
                        searchAndAddRow
                        if searchQuery.isEmpty {
                            skillCountRow
                        }
                        skillList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                if showSkillLimitBanner {
                    FloatingBanner(visible: showSkillLimitBanner,
                                   text: String(format: Str.skillLimitWarning, Str.skillsCount(MAX_RECOMMENDED_SKILL_COUNT)))
                        .padding(.top, 8)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { savedNamesAndDescriptions = skillManagerViewModel.getSelectedSkillsNamesAndDescriptions() }
        .onChange(of: uiState.skills.filter({ $0.skill.selected }).count) { count in
            if count > MAX_RECOMMENDED_SKILL_COUNT {
                showSkillLimitBanner = true
                Task { try? await Task.sleep(nanoseconds: 3_000_000_000); showSkillLimitBanner = false }
            }
        }
        .onChange(of: uiState.loading) { loading in
            if !loading && !hasDeterminedExpansion {
                isBuiltInExpanded = !uiState.skills.contains { !$0.skill.builtIn }
                hasDeterminedExpansion = true
            }
        }
        // Add sheets / dialogs
        .sheet(isPresented: $showAddSkillOptions) {
            AddSkillOptionsBottomSheet(onDismiss: { showAddSkillOptions = false }, onOptionSelected: { option in
                skillManagerViewModel.setValidationError(nil)
                switch option {
                case .featuredList: showAddFeatured = true
                case .remoteUrl: showAddFromUrl = true
                case .localImport: showDisclaimerSheet = true; pendingLocalImportOption = true
                case .viewCommunitySkills: showCommunitySkills = true
                }
                showAddSkillOptions = false
            })
        }
        .sheet(isPresented: $showAddFromUrl) {
            AddSkillFromUrlDialog(skillManagerViewModel: skillManagerViewModel,
                onDismissRequest: { showAddFromUrl = false },
                onSuccess: { showAddFromUrl = false })
        }
        .sheet(isPresented: $showAddFromLocal) {
            AddSkillFromLocalImportDialog(skillManagerViewModel: skillManagerViewModel,
                onDismissRequest: { showAddFromLocal = false },
                onSuccess: { showAddFromLocal = false })
        }
        .sheet(isPresented: $showAddFeatured) {
            AddSkillFromFeaturedListBottomSheet(skillManagerViewModel: skillManagerViewModel,
                onDismiss: { showAddFeatured = false },
                onSkillAdded: { showAddFeatured = false })
        }
        .sheet(isPresented: $showCommunitySkills) {
            ViewCommunitySkillsSheet(onDismiss: { showCommunitySkills = false })
        }
        .sheet(isPresented: $showAddOrEdit) {
            AddOrEditSkillBottomSheet(
                skillManagerViewModel: skillManagerViewModel,
                skillIndex: skillToEditIndex != -1 ? skillToEditIndex : uiState.skills.count,
                onDismiss: { showAddOrEdit = false; skillToEditIndex = -1 },
                onSuccess: { showAddOrEdit = false; skillToEditIndex = -1 })
        }
        .sheet(isPresented: $showSecretEditor) {
            if let state = uiState.skills.first(where: { uiState.skills.firstIndex(of: $0) == skillToEditIndex }) {
                SecretEditorDialogWrapper(skillState: state, skillManagerViewModel: skillManagerViewModel,
                    onDismiss: { showSecretEditor = false })
            }
        }
        .sheet(isPresented: $showDisclaimerSheet) {
            AddSkillDisclaimerDialog(
                onDismiss: { showDisclaimerSheet = false; pendingLocalImportOption = false },
                onConfirm: {
                    showDisclaimerSheet = false
                    if pendingLocalImportOption { showAddFromLocal = true }
                    pendingLocalImportOption = false
                })
        }
        .alert(inMultiSelectMode ? Str.deleteSelectedSkillsTitle : Str.deleteSkillDialogTitle, isPresented: $showDeleteAlert) {
            Button(Str.cancel, role: .cancel) { showDeleteAlert = false }
            Button(Str.delete, role: .destructive) {
                if inMultiSelectMode {
                    skillManagerViewModel.deleteSkills(names: selectedCustomSkillNames)
                    inMultiSelectMode = false; selectedCustomSkillNames.removeAll()
                } else {
                    skillManagerViewModel.deleteSkill(name: skillToDeleteName)
                }
                showDeleteAlert = false
            }
        } message: {
            Text(inMultiSelectMode
                 ? Str.deleteSelectedSkillsContent(selectedCustomSkillNames.count)
                 : Str.deleteSkillDialogContent)
        }
    }

    // MARK: - Sub-views

    private var normalHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Str.manageSkills).font(AppTypography.titleLarge)
                Text(Str.manageSkillsDescription).font(AppTypography.bodyMedium).foregroundColor(colors.onSurfaceVariant)
            }
            Spacer()
            Button(action: {
                onDismiss(savedNamesAndDescriptions != skillManagerViewModel.getSelectedSkillsNamesAndDescriptions())
            }) { Image(systemName: "xmark") }
        }
        .padding(.bottom, 8)
    }

    private var multiSelectHeader: some View {
        HStack {
            Button(action: { inMultiSelectMode = false; selectedCustomSkillNames.removeAll() }) {
                Image(systemName: "xmark")
            }
            Text(Str.selectedCustomSkillsCount(selectedCustomSkillNames.count))
                .font(AppTypography.titleMedium).padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { if !selectedCustomSkillNames.isEmpty { showDeleteAlert = true } }) {
                Image(systemName: "trash")
            }
        }
        .padding(.bottom, 8)
    }

    private var searchAndAddRow: some View {
        HStack(spacing: 12) {
            SearchBar(text: $searchQuery, placeholder: Str.searchSkill)
            Button(action: { searchQuery = ""; showAddSkillOptions = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(colors.primary)
                    .clipShape(Circle())
            }
        }
        .padding(.top, 8)
        .padding(.bottom, searchQuery.isEmpty ? 8 : 18)
    }

    private var skillCountRow: some View {
        HStack {
            Text(Str.skillsCount(uiState.skills.count)).font(AppTypography.labelLarge)
            Spacer()
            Button(Str.turnOnAll) { skillManagerViewModel.setAllSkillsSelected(selected: true) }.buttonStyle(.plain).foregroundColor(colors.primary)
            Button(Str.turnOffAll) { skillManagerViewModel.setAllSkillsSelected(selected: false) }.buttonStyle(.plain).foregroundColor(colors.primary)
        }
        .padding(.bottom, 8)
    }

    private var skillList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let builtIn = filteredSkills.filter { $0.skill.builtIn }
                let custom = filteredSkills.filter { !$0.skill.builtIn }

                if !builtIn.isEmpty {
                    sectionHeader(title: Str.builtInSkillsTitle, expanded: $isBuiltInExpanded)
                    if isBuiltInExpanded {
                        ForEach(builtIn) { state in skillRow(state) }
                    }
                }
                if !custom.isEmpty {
                    sectionHeader(title: Str.customSkillsTitle, expanded: $isCustomExpanded)
                    if isCustomExpanded {
                        ForEach(custom) { state in skillRow(state) }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, expanded: Binding<Bool>) -> some View {
        Button(action: { expanded.wrappedValue.toggle() }) {
            HStack {
                Text(title).font(AppTypography.titleMedium).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(colors.surfaceContainer).cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    private func skillRow(_ state: SkillState) -> some View {
        SkillItemRow(
            skillState: state,
            inMultiSelectMode: inMultiSelectMode,
            isSelectedForDeletion: selectedCustomSkillNames.contains(state.skill.name),
            onSelectionCheckedChange: { checked in
                if checked { selectedCustomSkillNames.insert(state.skill.name) }
                else {
                    selectedCustomSkillNames.remove(state.skill.name)
                    if selectedCustomSkillNames.isEmpty { inMultiSelectMode = false }
                }
            },
            onLongClick: {
                if !inMultiSelectMode && !state.skill.builtIn {
                    inMultiSelectMode = true; selectedCustomSkillNames.insert(state.skill.name)
                }
            },
            onSkillEnabledChange: { skillManagerViewModel.setSkillSelected(skill: state, selected: $0) },
            onViewClick: {
                skillToEditIndex = uiState.skills.firstIndex(of: state) ?? -1
                showAddOrEdit = true
            },
            onSecretClick: {
                skillToEditIndex = uiState.skills.firstIndex(of: state) ?? -1
                showSecretEditor = true
            },
            onDeleteClick: { skillToDeleteName = state.skill.name; showDeleteAlert = true },
            onHomepageClick: { if let url = URL(string: state.skill.homepage) { openURL(url) } }
        )
    }
}

// MARK: - SkillItemRow

struct SkillItemRow: View {
    let skillState: SkillState
    let inMultiSelectMode: Bool
    let isSelectedForDeletion: Bool
    let onSelectionCheckedChange: (Bool) -> Void
    let onLongClick: () -> Void
    let onSkillEnabledChange: (Bool) -> Void
    let onViewClick: () -> Void
    let onSecretClick: () -> Void
    let onDeleteClick: () -> Void
    let onHomepageClick: () -> Void

    @Environment(\.galleryColors) var colors
    @Environment(\.customColors) var customColors

    var body: some View {
        let skill = skillState.skill
        let isCustom = !skill.builtIn
        HStack(alignment: .center, spacing: 0) {
            if inMultiSelectMode && isCustom {
                Toggle("", isOn: Binding(get: { isSelectedForDeletion }, set: { onSelectionCheckedChange($0) }))
                    .labelsHidden().padding(.trailing, 8)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 2) {
                            if !skill.homepage.isEmpty {
                                Text(skill.name)
                                    .font(AppTypography.bodyMedium).fontWeight(.medium)
                                    .foregroundColor(customColors.linkColor)
                                    .underline()
                                    .onTapGesture { onHomepageClick() }
                                Image(systemName: "arrow.up.right.square").font(.system(size: 14)).foregroundColor(customColors.linkColor)
                            } else {
                                Text(skill.name).font(AppTypography.bodyMedium).fontWeight(.medium)
                            }
                        }
                        Text(skill.description.replacingOccurrences(of: "\n", with: " "))
                            .font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("", isOn: Binding(get: { skill.selected }, set: { onSkillEnabledChange($0) }))
                        .labelsHidden().disabled(inMultiSelectMode)
                        .offset(y: -4)
                }

                if !inMultiSelectMode {
                    HStack(spacing: 8) {
                        SmallFilledTonalButton(label: Str.view, systemImage: "eye", action: onViewClick)
                        if skill.requireSecret {
                            SmallFilledTonalButton(label: Str.secret, systemImage: "key", action: onSecretClick)
                        }
                        if isCustom {
                            SmallOutlinedButton(label: Str.delete, systemImage: "trash", action: onDeleteClick)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(colors.surfaceContainerLowest)
        .cornerRadius(20)
        .opacity((inMultiSelectMode && skill.builtIn) ? 0.5 : 1.0)
        .onLongPressGesture { onLongClick() }
        .onTapGesture { if inMultiSelectMode && isCustom { onSelectionCheckedChange(!isSelectedForDeletion) } }
    }
}

// MARK: - Add skill options

private enum AddSkillOptionType { case featuredList, remoteUrl, localImport, viewCommunitySkills }
private struct AddSkillOption { let type: AddSkillOptionType; let title: String; let description: String; let systemImage: String }
private let ADD_SKILL_OPTIONS: [AddSkillOption] = [
    AddSkillOption(type: .remoteUrl, title: Str.addSkillOptionUrlTitle, description: Str.addSkillOptionUrlDescription, systemImage: "link"),
    AddSkillOption(type: .localImport, title: Str.addSkillOptionLocalTitle, description: Str.addSkillOptionLocalDescription, systemImage: "folder"),
    AddSkillOption(type: .viewCommunitySkills, title: Str.addSkillOptionViewCommunitySkillsTitle, description: Str.addSkillOptionViewCommunitySkillsDescription, systemImage: "arrow.up.right.square"),
]

private struct AddSkillOptionsBottomSheet: View {
    let onDismiss: () -> Void
    let onOptionSelected: (AddSkillOptionType) -> Void
    @Environment(\.galleryColors) var colors

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(Str.addSkill).font(AppTypography.titleLarge).padding(.horizontal, 16).padding(.bottom, 16)
                ForEach(ADD_SKILL_OPTIONS, id: \.title) { option in
                    Button(action: { onOptionSelected(option.type); onDismiss() }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 16) {
                                Image(systemName: option.systemImage).frame(width: 24, height: 24)
                                Text(option.title).font(AppTypography.bodyLarge)
                            }
                            Text(option.description).font(AppTypography.bodySmall)
                                .foregroundColor(colors.onSurfaceVariant).padding(.leading, 40)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Community skills WebView sheet

private struct ViewCommunitySkillsSheet: View {
    let onDismiss: () -> Void
    @Environment(\.galleryColors) var colors

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Str.addSkillOptionViewCommunitySkillsTitle).font(AppTypography.titleLarge)
                        Text(Str.addSkillOptionViewCommunitySkillsDescription).font(AppTypography.bodyMedium).foregroundColor(colors.onSurfaceVariant)
                    }
                    Spacer()
                    Button(action: onDismiss) { Image(systemName: "xmark") }
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
                SafariWebView(url: URL(string: AgentSkillsURLs.DISCUSSIONS)!)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - SecretEditorDialog wrapper (reads existing secret)

private struct SecretEditorDialogWrapper: View {
    let skillState: SkillState
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    let onDismiss: () -> Void
    @State private var secret = ""

    var body: some View {
        SecretEditorDialog(
            title: Str.editSkill,
            fieldLabel: skillState.skill.requireSecretDescription,
            value: $secret,
            onDone: {
                skillManagerViewModel.dataStoreRepository.saveSecret(key: getSkillSecretKey(skillName: skillState.skill.name), value: secret)
                onDismiss()
            },
            onDismiss: onDismiss
        )
        .onAppear {
            secret = skillManagerViewModel.dataStoreRepository.readSecret(key: getSkillSecretKey(skillName: skillState.skill.name)) ?? ""
        }
    }
}

// MARK: - SkillState Equatable / index helpers
extension SkillState: Equatable {
    static func == (lhs: SkillState, rhs: SkillState) -> Bool { lhs.skill.name == rhs.skill.name }
}

// MARK: - SmallFilledTonalButton / SmallOutlinedButton (inline minimal versions)

private struct SmallFilledTonalButton: View {
    let label: String; let systemImage: String; let action: () -> Void
    @Environment(\.galleryColors) var colors
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 14))
                Text(label).font(AppTypography.labelMedium)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(colors.secondaryContainer).foregroundColor(colors.onSecondaryContainer)
        .controlSize(.small)
    }
}

private struct SmallOutlinedButton: View {
    let label: String; let systemImage: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 14))
                Text(label).font(AppTypography.labelMedium)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }
}

// MARK: - Strings not yet in Strings.swift

private extension Str {
    static let introducing = "Introducing"
    static let editSkill = "Edit secret"
    static let secret = "Secret"
    static let turnOnAll = "Turn on all"
    static let turnOffAll = "Turn off all"
    static let ok = "OK"
    static let done = "Done"
    static let view = "View"
    static let skillsCount: (Int) -> String = { "\($0) skill\($0 == 1 ? "" : "s")" }
    static func selectedCustomSkillsCount(_ n: Int) -> String { "\(n) selected" }
}
