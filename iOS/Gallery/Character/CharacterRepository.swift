// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of character/CharacterRepository.kt
//
// Android used SharedPreferences keyed under "character_store". iOS uses
// UserDefaults with the same logical keys. The public API is identical.

import Foundation
import Combine

/// Coins granted on first launch so the coin-unlock flow is usable without subscribing.
let welcomeCoins = 300

/// Bonus coins granted when the user (simulated-)subscribes to Pro.
let subscribeBonusCoins = 600

/// Persisted ownership/economy state for the companion characters.
struct CharacterState: Equatable {
    var coins: Int = 0
    var unlockedIds: Set<String> = []
    var selectedId: String = ""
    var isPro: Bool = false
    /// Per-character TTS voice id (e.g. "neural:kss", "neural:melo", "system:<name>").
    var voiceByCharacter: [String: String] = [:]
    /// Global default TTS voice id, used for any character without its own assigned voice.
    var defaultVoiceId: String = ""
}

/// Single source of truth for character ownership, the coin balance and the Pro flag.
///
/// State is persisted with `UserDefaults` (kept independent of the protobuf settings
/// store) and published via Combine so any screen reacts to changes. Purchases and
/// the subscription are simulated; a real billing backend can be wired in later
/// without changing callers.
final class CharacterRepository: ObservableObject {

    let characters: [Character] = Characters.all

    @Published private(set) var state: CharacterState

    private let defaults: UserDefaults
    private let suite = "com.google.ai.edge.gallery.character_store"

    // MARK: Init

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.google.ai.edge.gallery.character_store") ?? .standard) {
        self.defaults = defaults
        self.state = Self.load(from: defaults, characters: Characters.all)
    }

    // MARK: Persistence

    private static func load(from defaults: UserDefaults, characters: [Character]) -> CharacterState {
        let defaultSelected = characters.first?.id ?? ""
        return CharacterState(
            coins: defaults.object(forKey: Keys.coins) as? Int ?? welcomeCoins,
            unlockedIds: Set(defaults.stringArray(forKey: Keys.unlocked) ?? []),
            selectedId: defaults.string(forKey: Keys.selected) ?? defaultSelected,
            isPro: defaults.bool(forKey: Keys.isPro),
            voiceByCharacter: Self.decodeVoices(defaults.stringArray(forKey: Keys.voices) ?? []),
            defaultVoiceId: defaults.string(forKey: Keys.defaultVoice) ?? ""
        )
    }

    private func persist(_ newState: CharacterState) {
        defaults.set(newState.coins, forKey: Keys.coins)
        defaults.set(Array(newState.unlockedIds), forKey: Keys.unlocked)
        defaults.set(newState.selectedId, forKey: Keys.selected)
        defaults.set(newState.isPro, forKey: Keys.isPro)
        defaults.set(Self.encodeVoices(newState.voiceByCharacter), forKey: Keys.voices)
        defaults.set(newState.defaultVoiceId, forKey: Keys.defaultVoice)
        state = newState
    }

    // Voices are stored as ["characterId=voiceId", …] (voice ids never contain '=').
    private static func decodeVoices(_ raw: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for entry in raw {
            if let idx = entry.firstIndex(of: "=") {
                let key = String(entry[entry.startIndex..<idx])
                let val = String(entry[entry.index(after: idx)...])
                if !key.isEmpty { map[key] = val }
            }
        }
        return map
    }

    private static func encodeVoices(_ map: [String: String]) -> [String] {
        map.map { "\($0.key)=\($0.value)" }
    }

    // MARK: Voice

    func setVoiceForCharacter(_ characterId: String, voiceId: String) {
        var updated = state.voiceByCharacter
        updated[characterId] = voiceId
        persist(state.withVoiceByCharacter(updated))
    }

    func voiceForCharacter(_ characterId: String) -> String {
        state.voiceByCharacter[characterId] ?? ""
    }

    func setDefaultVoice(_ voiceId: String) {
        persist(state.withDefaultVoiceId(voiceId))
    }

    // MARK: Model-init deduplication

    // Transient (not persisted) marker of the last "model|character" the chat model
    // was initialized for, so we don't needlessly re-initialize on every screen return.
    private var lastInitSignature: String = ""

    /// Returns true (recording the new value) if `signature` differs from the last one initialized.
    func needsModelInit(signature: String) -> Bool {
        guard signature != lastInitSignature else { return false }
        lastInitSignature = signature
        return true
    }

    // MARK: Greeting

    // Transient request to have the character greet first when entering the chat.
    // Consumed by the chat screen once the model is ready.
    private var pendingGreetingId: String? = nil

    func requestGreeting(characterId: String) {
        pendingGreetingId = characterId
    }

    func isGreetingPending(characterId: String) -> Bool {
        pendingGreetingId == characterId
    }

    func clearGreeting() {
        pendingGreetingId = nil
    }

    // MARK: Unlock / selection

    /// Whether `character` is available to use (free, already purchased, or unlocked by Pro).
    func isUnlocked(_ character: Character) -> Bool {
        character.freeByDefault || state.isPro || state.unlockedIds.contains(character.id)
    }

    func isUnlocked(id: String) -> Bool {
        guard let c = Characters.byId(id) else { return false }
        return isUnlocked(c)
    }

    /// The currently selected character (falls back to the first one).
    func selectedCharacter() -> Character {
        Characters.byId(state.selectedId) ?? characters[0]
    }

    /// Selects `id` as the active character if it is unlocked.
    func select(id: String) {
        guard let character = Characters.byId(id),
              isUnlocked(character),
              state.selectedId != id else { return }
        persist(state.withSelectedId(id))
    }

    /// Attempts to unlock `character` by spending coins.
    /// Returns `true` if it is now unlocked, `false` if the user doesn't have enough coins.
    @discardableResult
    func tryUnlockWithCoins(_ character: Character) -> Bool {
        if isUnlocked(character) { return true }
        guard state.coins >= character.priceCoins else { return false }
        var newUnlocked = state.unlockedIds
        newUnlocked.insert(character.id)
        persist(state.withCoins(state.coins - character.priceCoins).withUnlockedIds(newUnlocked))
        return true
    }

    /// Adds coins to the balance (e.g. a reward).
    func addCoins(_ amount: Int) {
        guard amount != 0 else { return }
        persist(state.withCoins(state.coins + amount))
    }

    /// Simulates a successful Pro subscription: sets the flag and grants bonus coins.
    func subscribe() {
        persist(state.withIsPro(true).withCoins(state.coins + subscribeBonusCoins))
    }

    // MARK: Keys

    private enum Keys {
        static let coins = "coins"
        static let unlocked = "unlocked_ids"
        static let selected = "selected_id"
        static let isPro = "is_pro"
        static let voices = "voice_by_character"
        static let defaultVoice = "default_voice_id"
    }
}

// MARK: - CharacterState copy helpers (replaces Kotlin `data class copy`)

private extension CharacterState {
    func withCoins(_ v: Int) -> CharacterState {
        var s = self; s.coins = v; return s
    }
    func withUnlockedIds(_ v: Set<String>) -> CharacterState {
        var s = self; s.unlockedIds = v; return s
    }
    func withSelectedId(_ v: String) -> CharacterState {
        var s = self; s.selectedId = v; return s
    }
    func withIsPro(_ v: Bool) -> CharacterState {
        var s = self; s.isPro = v; return s
    }
    func withVoiceByCharacter(_ v: [String: String]) -> CharacterState {
        var s = self; s.voiceByCharacter = v; return s
    }
    func withDefaultVoiceId(_ v: String) -> CharacterState {
        var s = self; s.defaultVoiceId = v; return s
    }
}
