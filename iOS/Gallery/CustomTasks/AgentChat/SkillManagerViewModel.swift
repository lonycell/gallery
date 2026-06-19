// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/SkillManagerViewModel.kt

import Foundation
import SwiftUI

// MARK: - Constants

private let SKILL_ALLOWLIST_URL = ""
private let DEFAULT_DISABLED_SKILLS: Set<String> = ["calculate-hash", "kitchen-adventure", "text-spinner", "send-email"]

// MARK: - Try-out chips

let TRYOUT_CHIPS: [SkillTryOutChip] = [
    SkillTryOutChip(icon: "map",            label: "Interactive Map",     prompt: "Show me Googleplex on interactive map.",  skillName: "interactive-map"),
    SkillTryOutChip(icon: "bell",           label: "Schedule Reminder",   prompt: "Set a daily reminder at 9am to check my schedule for today.", skillName: "schedule-notification"),
    SkillTryOutChip(icon: "face.smiling",   label: "Track my mood",       prompt: "Log yesterday's mood as 2 because it was raining quite heavily, and log today's mood as 9 because I had a great time playing pickleball again. Then show me my mood dashboard.", skillName: "mood-tracker"),
    SkillTryOutChip(icon: "lightbulb",      label: "Learn something new", prompt: "I want to learn something new!",           skillName: "learn-something-new"),
    SkillTryOutChip(icon: "books.vertical", label: "Query Wikipedia",     prompt: "Check Wikipedia about Oscars 2026. Tell me who won the best picture.", skillName: "query-wikipedia"),
    SkillTryOutChip(icon: "qrcode",         label: "Generate QR code",    prompt: "Generate QR code for https://deepmind.google/models/gemma/", skillName: "qr-code"),
]

// MARK: - Skill source / action enums

enum SkillSource: String {
    case builtIn = "builtin"
    case featured = "featured"
    case remoteUrl = "remote_url"
    case localImport = "local_import"
    case unknown = "unknown"
}

enum SkillAction: String {
    case add = "add", delete = "delete"
    case enable = "enable", disable = "disable"
    case enableAll = "enable_all", disableAll = "disable_all"
}

// MARK: - State / UI models

struct SkillState: Identifiable {
    var skill: Skill
    var id: String { skill.name }
}

// NOTE: `AllowedSkill` and `SkillAllowlist` are provided by the foundation
// (Data/SkillAllowlist.swift) and reused here.

struct SkillManagerUiState {
    var loading: Bool = false
    var skills: [SkillState] = []
    var validating: Bool = false
    var validationError: String? = nil
    /// URL of the directory the user picked via the document picker.
    var importDirectoryURL: URL? = nil
    var loadingSkillAllowlist: Bool = false
    var featuredSkills: [AllowedSkill] = []
    var skillAllowlistError: String? = nil
}

// MARK: - ViewModel

/// Mirrors `SkillManagerViewModel` from Android.
/// Skills are stored in `DataStoreRepository` (skills.json) and bundled built-in skills are read
/// from `Bundle.main` under `skills/<name>/SKILL.md`.
@MainActor
final class SkillManagerViewModel: ObservableObject {
    @Published var uiState = SkillManagerUiState()

    let dataStoreRepository: DataStoreRepository
    private var skillLoaded = false

    init(dataStoreRepository: DataStoreRepository) {
        self.dataStoreRepository = dataStoreRepository
        if !SKILL_ALLOWLIST_URL.isEmpty {
            _Concurrency.Task { await loadSkillAllowlist() }
        }
    }

    // MARK: - Load skills

    func loadSkills() async {
        guard !skillLoaded else { return }
        setLoading(true)

        let allDataStoreSkills = dataStoreRepository.getAllSkills()
        let dataStoreBuiltInSkills = allDataStoreSkills.filter { $0.builtIn }
        let dataStoreCustomSkills = allDataStoreSkills.filter { !$0.builtIn }

        // Build a map: name → (selected, userModifiedSelection)
        var builtInSelectionMap: [String: (Bool, Bool)] = [:]
        for s in dataStoreBuiltInSkills {
            builtInSelectionMap[s.name] = (s.selected, s.userModifiedSelection)
        }

        // Read SKILL.md from bundled assets/skills/<dir>/SKILL.md
        var builtInSkills: [Skill] = []
        // NOTE: On iOS, bundled skills live under Bundle.main resources in a "skills" folder.
        // They are copied as folder references in Xcode. Enumerate sub-directories named "skills/*".
        if let skillsURL = Bundle.main.resourceURL?.appendingPathComponent("skills"),
           let subDirs = try? FileManager.default.contentsOfDirectory(at: skillsURL, includingPropertiesForKeys: nil) {
            for dirURL in subDirs {
                let skillMdURL = dirURL.appendingPathComponent("SKILL.md")
                if let mdContent = try? String(contentsOf: skillMdURL, encoding: .utf8) {
                    let importDir = "skills/\(dirURL.lastPathComponent)"
                    let (skillProto, errors) = convertSkillMdToProto(mdContent, builtIn: true, selected: true, importDir: importDir)
                    if errors.isEmpty, var skill = skillProto {
                        let defaultSelected = !DEFAULT_DISABLED_SKILLS.contains(skill.name)
                        if let (persisted, userModified) = builtInSelectionMap[skill.name] {
                            skill.selected = userModified ? persisted : defaultSelected
                            skill.userModifiedSelection = userModified
                        } else {
                            skill.selected = defaultSelected
                        }
                        builtInSkills.append(skill)
                    }
                }
            }
        }

        // Combine with custom skills
        var finalSkills = builtInSkills
        for custom in dataStoreCustomSkills {
            if !finalSkills.contains(where: { $0.name == custom.name }) {
                finalSkills.append(custom)
            }
        }

        dataStoreRepository.setSkills(finalSkills)
        uiState.skills = finalSkills.map { SkillState(skill: $0) }
        setLoading(false)
        skillLoaded = true
    }

    private func loadSkillAllowlist() async {
        uiState.loadingSkillAllowlist = true
        uiState.skillAllowlistError = nil
        do {
            guard let url = URL(string: SKILL_ALLOWLIST_URL) else { throw URLError(.badURL) }
            let (data, _) = try await URLSession.shared.data(from: url)
            let allowlist = try JSONDecoder().decode(SkillAllowlist.self, from: data)
            uiState.featuredSkills = allowlist.featuredSkills
            uiState.loadingSkillAllowlist = false
        } catch {
            uiState.skillAllowlistError = "Failed to load skill list: \(error.localizedDescription)"
            uiState.loadingSkillAllowlist = false
        }
    }

    // MARK: - Add from URL

    func validateAndAddSkillFromUrl(url: String, onSuccess: @escaping () -> Void, onValidationError: @escaping (String) -> Void) {
        setValidating(true)
        setValidationError(nil)
        _Concurrency.Task {
            var normalizedUrl = url
            if normalizedUrl.hasSuffix("/SKILL.md") { normalizedUrl = String(normalizedUrl.dropLast("/SKILL.md".count)) }
            if normalizedUrl.hasSuffix("/") { normalizedUrl = String(normalizedUrl.dropLast()) }
            let skillMdUrl = "\(normalizedUrl)/SKILL.md"

            do {
                guard let fetchUrl = URL(string: skillMdUrl) else { throw URLError(.badURL) }
                let (data, _) = try await URLSession.shared.data(from: fetchUrl)
                let mdContent = String(data: data, encoding: .utf8) ?? ""
                if mdContent.isEmpty {
                    let e = "SKILL.md is empty at \(skillMdUrl)"
                    setValidationError(e); setValidating(false); onValidationError(e); return
                }
                let (skillProto, errors) = convertSkillMdToProto(mdContent, builtIn: false, selected: true, skillUrl: normalizedUrl)
                if !errors.isEmpty {
                    let e = "Error parsing SKILL.md: \(errors.joined(separator: ", "))"
                    setValidationError(e); setValidating(false); onValidationError(e); return
                }
                if var skill = skillProto {
                    if uiState.skills.contains(where: { $0.skill.name == skill.name }) {
                        let e = "A skill with the name '\(skill.name)' already exists."
                        setValidationError(e); setValidating(false); onValidationError(e); return
                    }
                    addSkill(skill: skill, addToDataStore: true)
                }
                setValidating(false)
                onSuccess()
            } catch {
                let e = "Failed to fetch SKILL.md: \(error.localizedDescription)"
                setValidationError(e); setValidating(false); onValidationError(e)
            }
        }
    }

    // MARK: - Local import (document picker)

    /// Called after the user picks a directory via UIDocumentPickerViewController.
    /// The URL is the security-scoped URL of the picked directory.
    ///
    /// NOTE: iOS does not have Android's `OpenDocumentTree`/`DocumentFile` API.
    /// We use `UIDocumentPickerViewController` with `.init(forOpeningContentTypes: [.folder])`.
    /// The picked URL is stored in `uiState.importDirectoryURL`. Then this method copies
    /// the directory into the app's private files dir under `skills/<normalized-name>`.
    func validateAndAddSkillFromLocalImport(onSuccess: @escaping () -> Void, onValidationError: @escaping (String) -> Void) {
        setValidating(true)
        setValidationError(nil)
        guard let directoryURL = uiState.importDirectoryURL else {
            setValidating(false)
            let e = "No directory URL set."
            setValidationError(e); onValidationError(e); return
        }
        _Concurrency.Task {
            _ = directoryURL.startAccessingSecurityScopedResource()
            defer { directoryURL.stopAccessingSecurityScopedResource() }
            let skillMdURL = directoryURL.appendingPathComponent("SKILL.md")
            guard let mdContent = try? String(contentsOf: skillMdURL, encoding: .utf8), !mdContent.isEmpty else {
                let e = "SKILL.md not found in the selected directory."
                setValidationError(e); setValidating(false); onValidationError(e); return
            }
            let (skillProto, errors) = convertSkillMdToProto(mdContent, builtIn: false, selected: true)
            if !errors.isEmpty {
                let e = "Error parsing SKILL.md: \(errors.joined(separator: ", "))"
                setValidationError(e); setValidating(false); onValidationError(e); return
            }
            guard var skill = skillProto else {
                let e = "Unknown error during SKILL.md conversion."
                setValidationError(e); setValidating(false); onValidationError(e); return
            }
            // Check name conflict
            if uiState.skills.contains(where: { $0.skill.name == skill.name }) {
                let e = "A skill with the name '\(skill.name)' already exists."
                setValidationError(e); setValidating(false); onValidationError(e); return
            }
            let normalizedName = skill.name.replacingOccurrences(of: " ", with: "-")
            let destDir = FileSystem.appFilesDir.appendingPathComponent("skills/\(normalizedName)")
            let importDirName = "skills/\(normalizedName)"
            do {
                if FileManager.default.fileExists(atPath: destDir.path) {
                    try FileManager.default.removeItem(at: destDir)
                }
                try FileManager.default.copyItem(at: directoryURL, to: destDir)
            } catch {
                let e = "Failed to copy skill directory: \(error.localizedDescription)"
                setValidationError(e); setValidating(false); onValidationError(e); return
            }
            skill.importDirName = importDirName
            addSkill(skill: skill, addToDataStore: true)
            setValidating(false)
            setImportDirectoryURL(nil)
            onSuccess()
        }
    }

    func checkLocalSkillExisted(directoryURL: URL) -> Bool {
        let name = directoryURL.lastPathComponent.replacingOccurrences(of: " ", with: "-")
        let destDir = FileSystem.appFilesDir.appendingPathComponent("skills/\(name)")
        return FileManager.default.fileExists(atPath: destDir.path)
    }

    // MARK: - CRUD helpers

    func setLoading(_ loading: Bool) { uiState.loading = loading }
    func setValidating(_ v: Bool) { uiState.validating = v }
    func setValidationError(_ e: String?) { uiState.validationError = e }
    func setImportDirectoryURL(_ url: URL?) { uiState.importDirectoryURL = url }

    func addSkill(skill: Skill, addToDataStore: Bool) {
        let newState = SkillState(skill: skill)
        if skill.builtIn {
            uiState.skills.append(newState)
        } else {
            if let first = uiState.skills.firstIndex(where: { !$0.skill.builtIn }) {
                uiState.skills.insert(newState, at: first)
            } else {
                uiState.skills.append(newState)
            }
        }
        if addToDataStore {
            dataStoreRepository.addSkill(skill)
        }
    }

    func deleteSkill(name: String) {
        uiState.skills.removeAll { $0.skill.name == name }
        _Concurrency.Task {
            // Delete imported files
            if let skill = uiState.skills.first(where: { $0.skill.name == name })?.skill,
               !skill.importDirName.isEmpty {
                let skillDir = FileSystem.appFilesDir.appendingPathComponent(skill.importDirName)
                try? FileManager.default.removeItem(at: skillDir)
            }
            dataStoreRepository.deleteSkill(name: name)
        }
    }

    func deleteSkills(names: Set<String>) {
        let toDelete = uiState.skills.filter { names.contains($0.skill.name) }.map { $0.skill }
        uiState.skills.removeAll { names.contains($0.skill.name) }
        _Concurrency.Task {
            for skill in toDelete where !skill.importDirName.isEmpty {
                let skillDir = FileSystem.appFilesDir.appendingPathComponent(skill.importDirName)
                try? FileManager.default.removeItem(at: skillDir)
            }
            await dataStoreRepository.deleteSkills(names: names)
        }
    }

    func setSkillSelected(skill: SkillState, selected: Bool) {
        if let i = uiState.skills.firstIndex(where: { $0.skill.name == skill.skill.name }) {
            uiState.skills[i].skill.selected = selected
        }
        _Concurrency.Task { dataStoreRepository.setSkillSelected(skill.skill, selected: selected) }
    }

    func setAllSkillsSelected(selected: Bool) {
        uiState.skills = uiState.skills.map { var s = $0; s.skill.selected = selected; return s }
        _Concurrency.Task { dataStoreRepository.setAllSkillsSelected(selected) }
    }

    func getSelectedSkills() -> [Skill] { uiState.skills.filter { $0.skill.selected }.map { $0.skill } }

    func getSkill(name: String) -> Skill? { uiState.skills.first(where: { $0.skill.name == name })?.skill }

    func isSkillSelected(skillName: String) -> Bool {
        uiState.skills.first(where: { $0.skill.name == skillName })?.skill.selected == true
    }

    func getSelectedSkillsNamesAndDescriptions() -> String {
        getSelectedSkills().map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
    }

    // MARK: - Skill URL helpers

    func getJsSkillUrl(skillName: String, scriptName: String) -> String? {
        guard let skill = getSkill(name: skillName) else { return nil }
        var baseUrl = ""
        if !skill.importDirName.isEmpty {
            // NOTE: LOCAL_URL_BASE is the WKWebView-served local files base URL.
            // On iOS, WKWebView can load files from the app's Documents/Library directory
            // using `loadFileURL(_:allowingReadAccessTo:)`. The base here mirrors Android's
            // LOCAL_URL_BASE constant which was used with Android's WebView asset loader.
            baseUrl = "\(LOCAL_URL_BASE)/\(skill.importDirName)"
        } else if !skill.skillUrl.isEmpty {
            baseUrl = skill.skillUrl
        }
        guard !baseUrl.isEmpty else { return nil }
        return "\(baseUrl)/scripts/\(scriptName)"
    }

    func getJsSkillWebviewUrl(skillName: String, url: String) -> String {
        guard let skill = getSkill(name: skillName) else { return url }
        if url.hasPrefix("http") { return url }
        var baseUrl = ""
        if !skill.importDirName.isEmpty {
            baseUrl = "\(LOCAL_URL_BASE)/\(skill.importDirName)"
        } else if !skill.skillUrl.isEmpty {
            baseUrl = skill.skillUrl
        }
        guard !baseUrl.isEmpty else { return url }
        return "\(baseUrl)/assets/\(url)"
    }

    // MARK: - Save / edit skill

    func saveSkillEdit(index: Int, name: String, description: String, instructions: String, scriptsContent: [String: String], onSuccess: @escaping () -> Void, onError: @escaping (String) -> Void) {
        _Concurrency.Task {
            let isNew = index < 0 || index >= uiState.skills.count
            if isNew {
                if uiState.skills.contains(where: { $0.skill.name == name }) {
                    onError("A skill with the name '\(name)' already exists."); return
                }
                let normalizedName = name.replacingOccurrences(of: " ", with: "-")
                let skillDestDir = FileSystem.appFilesDir.appendingPathComponent("skills/\(normalizedName)")
                let scriptDestDir = skillDestDir.appendingPathComponent("scripts")
                try? FileManager.default.removeItem(at: skillDestDir)
                try? FileManager.default.createDirectory(at: scriptDestDir, withIntermediateDirectories: true)
                writeSkillMd(at: skillDestDir.appendingPathComponent("SKILL.md"), name: normalizedName, description: description, instructions: instructions)
                saveScripts(scriptDestDir: scriptDestDir, scriptsContent: scriptsContent)
                let newSkill = Skill(name: normalizedName, description: description, instructions: instructions, builtIn: false, skillUrl: "", importDirName: "skills/\(normalizedName)", selected: true)
                addSkill(skill: newSkill, addToDataStore: true)
                onSuccess()
            } else {
                var existing = uiState.skills[index].skill
                let oldName = existing.name
                if existing.builtIn { onError("Cannot edit built-in skills."); return }
                let normalizedNewName = name.replacingOccurrences(of: " ", with: "-")
                if oldName != normalizedNewName && uiState.skills.contains(where: { $0.skill.name == normalizedNewName }) {
                    onError("A skill with the name '\(normalizedNewName)' already exists."); return
                }
                var updatedImportDir = existing.importDirName
                if oldName != normalizedNewName {
                    let oldDir = FileSystem.appFilesDir.appendingPathComponent(existing.importDirName)
                    let newDir = FileSystem.appFilesDir.appendingPathComponent("skills/\(normalizedNewName)")
                    if FileManager.default.fileExists(atPath: oldDir.path) {
                        try? FileManager.default.moveItem(at: oldDir, to: newDir)
                    } else {
                        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
                    }
                    updatedImportDir = "skills/\(normalizedNewName)"
                }
                let skillDir = FileSystem.appFilesDir.appendingPathComponent(updatedImportDir)
                writeSkillMd(at: skillDir.appendingPathComponent("SKILL.md"), name: normalizedNewName, description: description, instructions: instructions)
                let scriptDir = skillDir.appendingPathComponent("scripts")
                try? FileManager.default.removeItem(at: scriptDir)
                try? FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
                saveScripts(scriptDestDir: scriptDir, scriptsContent: scriptsContent)
                existing.name = normalizedNewName
                existing.description = description
                existing.instructions = instructions
                existing.importDirName = updatedImportDir
                if let i = uiState.skills.firstIndex(where: { $0.skill.name == oldName }) {
                    uiState.skills[i].skill = existing
                }
                // Update data store
                var all = dataStoreRepository.getAllSkills()
                all = all.map { $0.name == oldName ? existing : $0 }
                dataStoreRepository.setSkills(all)
                onSuccess()
            }
        }
    }

    func loadSkillScriptsContent(skill: Skill, onDone: @escaping ([String: String]) -> Void) {
        _Concurrency.Task {
            guard !skill.importDirName.isEmpty else { onDone([:]); return }
            let scriptDir = FileSystem.appFilesDir.appendingPathComponent(skill.importDirName).appendingPathComponent("scripts")
            guard let files = try? FileManager.default.contentsOfDirectory(at: scriptDir, includingPropertiesForKeys: nil) else { onDone([:]); return }
            var result: [String: String] = [:]
            for file in files {
                let ext = file.pathExtension
                if ext == "html" || ext == "js" {
                    result[file.lastPathComponent] = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                }
            }
            onDone(result)
        }
    }

    func deleteSkillScript(skill: Skill, scriptName: String) {
        guard !skill.importDirName.isEmpty else { return }
        let file = FileSystem.appFilesDir.appendingPathComponent(skill.importDirName).appendingPathComponent("scripts/\(scriptName)")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Analytics helpers

    func getSkillShortId(_ skill: Skill) -> String {
        let source = getSkillSource(skill)
        let identifier: String
        switch source {
        case .builtIn, .featured: identifier = skill.name
        case .localImport: identifier = skill.importDirName
        default: identifier = skill.skillUrl
        }
        guard !identifier.isEmpty else { return "xxxx" }
        let prefix: String
        switch source {
        case .builtIn: prefix = "b_"
        case .featured: prefix = "f_"
        case .localImport: prefix = "l_"
        default: prefix = "c_"
        }
        guard let data = identifier.data(using: .utf8) else { return prefix + "fail" }
        var digest = [UInt8](repeating: 0, count: 32)
        // NOTE: CryptoKit requires iOS 13+, which is our minimum.
        // We use a simple FNV-1a hash as a lightweight stand-in.
        var hash: UInt32 = 2166136261
        for byte in data { hash = (hash ^ UInt32(byte)) &* 16777619 }
        let hex = String(format: "%08x", hash)
        return prefix + String(hex.prefix(4))
    }

    private func getSkillSource(_ skill: Skill) -> SkillSource {
        let isFeatured = !skill.skillUrl.isEmpty && uiState.featuredSkills.contains(where: { $0.skillUrl == skill.skillUrl })
        if skill.builtIn { return .builtIn }
        if isFeatured { return .featured }
        if !skill.skillUrl.isEmpty { return .remoteUrl }
        if !skill.importDirName.isEmpty { return .localImport }
        return .unknown
    }

    // MARK: - SKILL.md parsing

    func convertSkillMdToProto(_ mdContent: String, builtIn: Bool, selected: Bool, skillUrl: String = "", importDir: String = "") -> (Skill?, [String]) {
        let parts = mdContent.components(separatedBy: "---")
        var errors: [String] = []
        guard parts.count >= 3 else {
            errors.append("Invalid format: Expected at least two '---' sections.")
            return (nil, errors)
        }
        let header = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        var name: String? = nil
        var description: String? = nil
        var requireSecret = false
        var requireSecretDescription = ""
        var homepage = ""
        var inMetadata = false
        for line in header.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "metadata:" { inMetadata = true; continue }
            if !inMetadata {
                if t.hasPrefix("name:") { name = String(t.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces) }
                else if t.hasPrefix("description:") { description = String(t.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces) }
            } else {
                if t.hasPrefix("require-secret:") { requireSecret = String(t.dropFirst("require-secret:".count)).trimmingCharacters(in: .whitespaces) == "true" }
                else if t.hasPrefix("require-secret-description:") { requireSecretDescription = String(t.dropFirst("require-secret-description:".count)).trimmingCharacters(in: .whitespaces) }
                else if t.hasPrefix("homepage:") { homepage = String(t.dropFirst("homepage:".count)).trimmingCharacters(in: .whitespaces) }
            }
        }
        if (name ?? "").isEmpty { errors.append("Missing or empty 'name' in the header.") }
        if (description ?? "").isEmpty { errors.append("Missing or empty 'description' in the header.") }
        guard errors.isEmpty, let n = name, let d = description else { return (nil, errors) }
        let instructions = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
        let skill = Skill(name: n, description: d, instructions: instructions, builtIn: builtIn, skillUrl: skillUrl, importDirName: importDir, selected: selected, requireSecret: requireSecret, requireSecretDescription: requireSecretDescription, homepage: homepage, userModifiedSelection: false)
        return (skill, [])
    }

    // MARK: - Private helpers

    private func writeSkillMd(at url: URL, name: String, description: String, instructions: String) {
        let md = "---\nname: \(name)\ndescription: \(description)\n---\n\n\(instructions)"
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    private func saveScripts(scriptDestDir: URL, scriptsContent: [String: String]) {
        for (name, content) in scriptsContent {
            let file = scriptDestDir.appendingPathComponent(name)
            try? content.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Helpers

func getSkillSecretKey(skillName: String) -> String { "skill___\(skillName)" }

/// The base URL prefix used for locally-served skill resources from WKWebView.
/// NOTE: On iOS there is no Android-style `WebViewAssetLoader`. We use a WKURLSchemeHandler
/// registered under a custom scheme (e.g. "gallery-local://") to serve files from the app's
/// private files directory. Replace this constant and the WKWebView setup in AgentChatScreen
/// to match the registered scheme.
let LOCAL_URL_BASE = "gallery-local:/"

// NOTE: `FileSystem.appFilesDir` is provided by the foundation (Common/Utils.swift).
