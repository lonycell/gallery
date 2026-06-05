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

// Port of character/CharacterViewModel.kt
//
// Kotlin @HiltViewModel → @MainActor final class CharacterViewModel: ObservableObject.
// The repository is a reference type; every CharacterViewModel instance observes the
// same state, so a selection/unlock made on one screen is immediately reflected on
// all others (via Combine @Published).

import Foundation
import Combine

@MainActor
final class CharacterViewModel: ObservableObject {

    let characters: [Character]

    /// Forwarded from the repository's @Published state so SwiftUI views can observe it
    /// directly via `@StateObject` / `@ObservedObject`.
    @Published private(set) var state: CharacterState

    private let repository: CharacterRepository
    private var cancellable: AnyCancellable?

    // MARK: Init

    init(repository: CharacterRepository) {
        self.repository = repository
        self.characters = repository.characters
        self.state = repository.state
        // Forward repository changes to this VM's @Published state.
        cancellable = repository.$state.sink { [weak self] newState in
            self?.state = newState
        }
    }

    // MARK: Queries

    func isUnlocked(_ character: Character) -> Bool {
        repository.isUnlocked(character)
    }

    func characterById(_ id: String) -> Character? {
        Characters.byId(id)
    }

    func selectedCharacter() -> Character {
        repository.selectedCharacter()
    }

    // MARK: Mutations

    func select(id: String) {
        repository.select(id: id)
    }

    @discardableResult
    func tryUnlockWithCoins(_ character: Character) -> Bool {
        repository.tryUnlockWithCoins(character)
    }

    func subscribe() {
        repository.subscribe()
    }

    func setVoiceForCharacter(_ characterId: String, voiceId: String) {
        repository.setVoiceForCharacter(characterId, voiceId: voiceId)
    }

    func voiceForCharacter(_ characterId: String) -> String {
        repository.voiceForCharacter(characterId)
    }

    func setDefaultVoice(_ voiceId: String) {
        repository.setDefaultVoice(voiceId)
    }

    func needsModelInit(signature: String) -> Bool {
        repository.needsModelInit(signature: signature)
    }

    func requestGreeting(characterId: String) {
        repository.requestGreeting(characterId: characterId)
    }

    func isGreetingPending(characterId: String) -> Bool {
        repository.isGreetingPending(characterId: characterId)
    }

    func clearGreeting() {
        repository.clearGreeting()
    }
}
