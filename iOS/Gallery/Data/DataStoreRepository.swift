/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/DataStoreRepository.kt
//
// Android backed five Jetpack DataStore<proto> stores (settings, user_data,
// cutouts, benchmark_results, skills) and accessed them synchronously via
// runBlocking. iOS mirrors that with five JSON files in the app's private files
// directory, read/written synchronously behind a lock — keeping the exact same
// blocking API the Android call sites expect, plus async update helpers used by
// SystemPromptRepository.

import Foundation

/// Repository facade over the persisted proto stores. Mirrors `DataStoreRepository`.
protocol DataStoreRepository: AnyObject {
  func saveTextInputHistory(_ history: [String])
  func readTextInputHistory() -> [String]
  func saveTheme(_ theme: Theme)
  func readTheme() -> Theme
  func saveSecret(key: String, value: String)
  func readSecret(key: String) -> String?
  func deleteSecret(key: String)
  func saveAccessTokenData(accessToken: String, refreshToken: String, expiresAt: Int64)
  func clearAccessTokenData()
  func readAccessTokenData() -> AccessTokenData?
  func saveImportedModels(_ importedModels: [ImportedModel])
  func readImportedModels() -> [ImportedModel]
  func isTosAccepted() -> Bool
  func acceptTos()
  func isGemmaTermsOfUseAccepted() -> Bool
  func acceptGemmaTermsOfUse()
  func getHasRunTinyGarden() -> Bool
  func setHasRunTinyGarden(_ hasRun: Bool)
  func addCutout(_ cutout: Cutout)
  func getAllCutouts() -> [Cutout]
  func setCutout(_ newCutout: Cutout)
  func setCutouts(_ cutouts: [Cutout])
  func setHasSeenBenchmarkComparisonHelp(_ seen: Bool)
  func getHasSeenBenchmarkComparisonHelp() -> Bool
  func addBenchmarkResult(_ result: BenchmarkResult)
  func getAllBenchmarkResults() -> [BenchmarkResult]
  func deleteBenchmarkResult(index: Int)
  func addSkill(_ skill: Skill)
  func setSkills(_ skills: [Skill])
  func setSkillSelected(_ skill: Skill, selected: Bool)
  func setAllSkillsSelected(_ selected: Bool)
  func getAllSkills() -> [Skill]
  func deleteSkill(name: String)
  func deleteSkills(names: Set<String>) async
  func addViewedPromoId(promoId: String)
  func removeViewedPromoId(promoId: String)
  func hasViewedPromo(promoId: String) -> Bool

  // Lower-level UserData accessors used by SystemPromptRepository / MCP / chat.
  func readUserData() -> UserData
  func updateUserData(_ transform: (inout UserData) -> Void) async
}

final class DefaultDataStoreRepository: DataStoreRepository {
  private let lock = NSLock()
  private let dir = FileSystem.appFilesDir

  private lazy var settingsURL = dir.appendingPathComponent("settings.json")
  private lazy var userDataURL = dir.appendingPathComponent("user_data.json")
  private lazy var cutoutsURL = dir.appendingPathComponent("cutouts.json")
  private lazy var benchmarkURL = dir.appendingPathComponent("benchmark_results.json")
  private lazy var skillsURL = dir.appendingPathComponent("skills.json")

  // MARK: - Generic JSON load/save

  private func load<T: Codable>(_ url: URL, default def: T) -> T {
    lock.lock(); defer { lock.unlock() }
    guard let data = try? Data(contentsOf: url),
          let value = try? JSONDecoder().decode(T.self, from: data) else { return def }
    return value
  }

  private func save<T: Codable>(_ value: T, to url: URL) {
    lock.lock(); defer { lock.unlock() }
    if let data = try? JSONEncoder().encode(value) { try? data.write(to: url) }
  }

  private func settings() -> Settings { load(settingsURL, default: .defaultInstance) }
  private func mutateSettings(_ block: (inout Settings) -> Void) {
    var s = settings(); block(&s); save(s, to: settingsURL)
  }
  private func userData() -> UserData { load(userDataURL, default: .defaultInstance) }
  private func mutateUserData(_ block: (inout UserData) -> Void) {
    var u = userData(); block(&u); save(u, to: userDataURL)
  }

  // MARK: - Text input history / theme

  func saveTextInputHistory(_ history: [String]) { mutateSettings { $0.textInputHistory = history } }
  func readTextInputHistory() -> [String] { settings().textInputHistory }
  func saveTheme(_ theme: Theme) { mutateSettings { $0.theme = theme } }
  func readTheme() -> Theme {
    let t = settings().theme
    return t == .themeUnspecified ? .themeAuto : t
  }

  // MARK: - Secrets / access token (stored in UserData.secrets, matching Android)

  func saveSecret(key: String, value: String) { mutateUserData { $0.secrets[key] = value } }
  func readSecret(key: String) -> String? { userData().secrets[key] }
  func deleteSecret(key: String) { mutateUserData { $0.secrets.removeValue(forKey: key) } }

  func saveAccessTokenData(accessToken: String, refreshToken: String, expiresAt: Int64) {
    mutateUserData {
      $0.accessTokenData = AccessTokenData(accessToken: accessToken, refreshToken: refreshToken, expiresAtMs: expiresAt)
    }
  }
  func clearAccessTokenData() { mutateUserData { $0.accessTokenData = nil } }
  func readAccessTokenData() -> AccessTokenData? { userData().accessTokenData }

  // MARK: - Imported models

  func saveImportedModels(_ importedModels: [ImportedModel]) { mutateSettings { $0.importedModel = importedModels } }
  func readImportedModels() -> [ImportedModel] { settings().importedModel }

  // MARK: - TOS / Gemma terms / tiny garden flags

  func isTosAccepted() -> Bool { settings().isTosAccepted }
  func acceptTos() { mutateSettings { $0.isTosAccepted = true } }
  func isGemmaTermsOfUseAccepted() -> Bool { settings().isGemmaTermsAccepted }
  func acceptGemmaTermsOfUse() { mutateSettings { $0.isGemmaTermsAccepted = true } }
  func getHasRunTinyGarden() -> Bool { settings().hasRunTinyGarden }
  func setHasRunTinyGarden(_ hasRun: Bool) { mutateSettings { $0.hasRunTinyGarden = hasRun } }

  // MARK: - Cutouts

  private func cutoutsCollection() -> CutoutCollection { load(cutoutsURL, default: .defaultInstance) }
  func addCutout(_ cutout: Cutout) {
    var c = cutoutsCollection(); c.cutout.append(cutout); save(c, to: cutoutsURL)
  }
  func getAllCutouts() -> [Cutout] { cutoutsCollection().cutout }
  func setCutout(_ newCutout: Cutout) {
    var c = cutoutsCollection()
    if let i = c.cutout.firstIndex(where: { $0.id == newCutout.id }) { c.cutout[i] = newCutout }
    save(c, to: cutoutsURL)
  }
  func setCutouts(_ cutouts: [Cutout]) {
    var c = cutoutsCollection(); c.cutout = cutouts; save(c, to: cutoutsURL)
  }

  // MARK: - Benchmark

  func setHasSeenBenchmarkComparisonHelp(_ seen: Bool) { mutateSettings { $0.hasSeenBenchmarkComparisonHelp = seen } }
  func getHasSeenBenchmarkComparisonHelp() -> Bool { settings().hasSeenBenchmarkComparisonHelp }
  private func benchmarkResults() -> BenchmarkResults { load(benchmarkURL, default: .defaultInstance) }
  func addBenchmarkResult(_ result: BenchmarkResult) {
    var r = benchmarkResults(); r.result.append(result); save(r, to: benchmarkURL)
  }
  func getAllBenchmarkResults() -> [BenchmarkResult] { benchmarkResults().result }
  func deleteBenchmarkResult(index: Int) {
    var r = benchmarkResults()
    guard r.result.indices.contains(index) else { return }
    r.result.remove(at: index); save(r, to: benchmarkURL)
  }

  // MARK: - Skills

  private func skillsCollection() -> Skills { load(skillsURL, default: .defaultInstance) }
  func addSkill(_ skill: Skill) {
    var s = skillsCollection()
    s.skill.removeAll { $0.name == skill.name }
    s.skill.append(skill)
    save(s, to: skillsURL)
  }
  func setSkills(_ skills: [Skill]) { var s = skillsCollection(); s.skill = skills; save(s, to: skillsURL) }
  func setSkillSelected(_ skill: Skill, selected: Bool) {
    var s = skillsCollection()
    s.skill = s.skill.map { var c = $0; if c.name == skill.name { c.selected = selected }; return c }
    save(s, to: skillsURL)
  }
  func setAllSkillsSelected(_ selected: Bool) {
    var s = skillsCollection()
    s.skill = s.skill.map { var c = $0; c.selected = selected; return c }
    save(s, to: skillsURL)
  }
  func getAllSkills() -> [Skill] { skillsCollection().skill }
  func deleteSkill(name: String) {
    var s = skillsCollection(); s.skill.removeAll { $0.name == name }; save(s, to: skillsURL)
  }
  func deleteSkills(names: Set<String>) async {
    var s = skillsCollection(); s.skill.removeAll { names.contains($0.name) }; save(s, to: skillsURL)
  }

  // MARK: - Promo ids

  func addViewedPromoId(promoId: String) {
    mutateSettings { if !$0.viewedPromoId.contains(promoId) { $0.viewedPromoId.append(promoId) } }
  }
  func removeViewedPromoId(promoId: String) {
    mutateSettings { $0.viewedPromoId.removeAll { $0 == promoId } }
  }
  func hasViewedPromo(promoId: String) -> Bool { settings().viewedPromoId.contains(promoId) }

  // MARK: - UserData accessors

  func readUserData() -> UserData { userData() }
  func updateUserData(_ transform: (inout UserData) -> Void) async { mutateUserData(transform) }
}
