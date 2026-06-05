// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AddSkillFromFeaturedListBottomSheet.kt

import SwiftUI

struct AddSkillFromFeaturedListBottomSheet: View {
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    let onDismiss: () -> Void
    let onSkillAdded: () -> Void

    @State private var searchQuery = ""
    @State private var showDisclaimerSheet = false
    @State private var skillToAdd: AllowedSkill?
    @State private var skillValidationErrors: [String: String] = [:]
    @State private var validatingSkills: Set<String> = []
    @Environment(\.galleryColors) var colors
    @Environment(\.openURL) var openURL

    private var uiState: SkillManagerUiState { skillManagerViewModel.uiState }

    private var filteredSkills: [AllowedSkill] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return uiState.featuredSkills }
        return uiState.featuredSkills.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Str.featuredSkillsTitle).font(AppTypography.titleLarge)
                        Text(Str.featuredSkillsDescription).font(AppTypography.bodyMedium)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    Spacer()
                    Button(action: onDismiss) { Image(systemName: "xmark") }
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

                if uiState.loadingSkillAllowlist {
                    HStack(spacing: 8) {
                        ProgressView().frame(width: 20, height: 20)
                        Text(Str.loadingSkillsAllowlist).font(AppTypography.bodyMedium)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                } else if let err = uiState.skillAllowlistError {
                    Text(err).font(AppTypography.bodyMedium).foregroundColor(colors.error)
                        .padding(.vertical, 16).padding(.horizontal, 16)
                } else {
                    SearchBar(text: $searchQuery, placeholder: Str.searchSkill)
                        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSkills, id: \.skillUrl) { skill in
                                FeaturedSkillItemView(
                                    skill: skill,
                                    validationError: skillValidationErrors[skill.skillUrl],
                                    isAdding: validatingSkills.contains(skill.skillUrl),
                                    isSkillAdded: uiState.skills.contains(where: { $0.skill.name == skill.name }),
                                    onAddClick: { handleAddSkill(skill) },
                                    onAttributionClick: {
                                        if let url = URL(string: skill.attributionUrl ?? "") { openURL(url) }
                                    })
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 16)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showDisclaimerSheet) {
            if let skill = skillToAdd {
                AddSkillDisclaimerDialog(
                    onDismiss: { showDisclaimerSheet = false; skillToAdd = nil },
                    onConfirm: {
                        showDisclaimerSheet = false
                        let url = skill.skillUrl
                        validatingSkills.insert(url)
                        skillManagerViewModel.validateAndAddSkillFromUrl(url: url, onSuccess: {
                            validatingSkills.remove(url); onDismiss(); onSkillAdded()
                        }, onValidationError: { err in
                            validatingSkills.remove(url); skillValidationErrors[url] = err
                        })
                        skillToAdd = nil
                    })
            }
        }
    }

    private func handleAddSkill(_ skill: AllowedSkill) {
        let url = skill.skillUrl
        if isSkillHostApproved(url) {
            validatingSkills.insert(url)
            skillManagerViewModel.validateAndAddSkillFromUrl(url: url, onSuccess: {
                validatingSkills.remove(url); onDismiss(); onSkillAdded()
            }, onValidationError: { err in
                validatingSkills.remove(url); skillValidationErrors[url] = err
            })
        } else {
            skillToAdd = skill
            showDisclaimerSheet = true
        }
    }
}

// MARK: - Featured skill item row

private struct FeaturedSkillItemView: View {
    let skill: AllowedSkill
    let validationError: String?
    let isAdding: Bool
    let isSkillAdded: Bool
    let onAddClick: () -> Void
    let onAttributionClick: () -> Void

    @Environment(\.galleryColors) var colors
    @Environment(\.customColors) var customColors

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(skill.name).font(AppTypography.bodyLarge).fontWeight(.medium)
                if let label = skill.attributionLabel {
                    let hasUrl = !(skill.attributionUrl ?? "").isEmpty
                    HStack(spacing: 2) {
                        Text(label)
                            .font(AppTypography.bodySmall)
                            .foregroundColor(hasUrl ? colors.primary : colors.onSurfaceVariant)
                            .underline(hasUrl)
                            .onTapGesture { if hasUrl { onAttributionClick() } }
                        if hasUrl { Image(systemName: "arrow.up.right.square").font(.system(size: 12)).foregroundColor(colors.primary) }
                    }
                    .padding(.top, 2)
                }
                Text(skill.description)
                    .font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant)
                    .padding(.top, 12)
                if let err = validationError {
                    Text(err).font(AppTypography.bodySmall).foregroundColor(colors.error).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isAdding {
                    ProgressView().frame(width: 24, height: 24)
                } else if isSkillAdded {
                    Button(Str.added) {}
                        .buttonStyle(.borderedProminent).disabled(true).font(AppTypography.labelMedium)
                } else {
                    Button(action: onAddClick) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 14))
                            Text(Str.add).font(AppTypography.labelMedium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 4).padding(.trailing, 8)
        }
        .padding(.vertical, 12).padding(.leading, 16)
        .background(colors.surfaceContainerLowest)
        .cornerRadius(20)
    }
}

// MARK: - SearchBar helper

private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.galleryColors) var colors

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(colors.onSurfaceVariant)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button(action: { text = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(colors.onSurfaceVariant) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(colors.surfaceContainerHigh)
        .clipShape(Capsule())
    }
}
