/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.google.ai.edge.gallery.character

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

/**
 * Thin ViewModel over [CharacterRepository] for the character-selection UI and the chat screen.
 *
 * Because the repository is a singleton exposing a single [StateFlow], every instance of this
 * ViewModel observes the same state — so a selection/unlock made on one screen is reflected on the
 * others immediately.
 */
@HiltViewModel
class CharacterViewModel @Inject constructor(private val repository: CharacterRepository) :
  ViewModel() {

  // Computed (not cached) so it reflects the latest customizations. The selection screen reads
  // `state`, so a recomposition on any override change re-reads this merged list.
  val characters: List<Character>
    get() = repository.characters

  val state: StateFlow<CharacterState> = repository.state

  fun isUnlocked(character: Character): Boolean = repository.isUnlocked(character)

  fun select(id: String) = repository.select(id)

  fun tryUnlockWithCoins(character: Character): Boolean = repository.tryUnlockWithCoins(character)

  fun subscribe() = repository.subscribe()

  fun setVoiceForCharacter(characterId: String, voiceId: String) =
    repository.setVoiceForCharacter(characterId, voiceId)

  fun voiceForCharacter(characterId: String): String = repository.voiceForCharacter(characterId)

  fun setDefaultVoice(voiceId: String) = repository.setDefaultVoice(voiceId)

  /** Sets the global tool model (empty = "auto"). See docs/TOOL_ROUTER_PLAN.md. */
  fun setToolModel(modelName: String) = repository.setToolModel(modelName)

  fun needsModelInit(signature: String): Boolean = repository.needsModelInit(signature)

  fun requestGreeting(characterId: String) = repository.requestGreeting(characterId)

  fun isGreetingPending(characterId: String): Boolean = repository.isGreetingPending(characterId)

  fun clearGreeting() = repository.clearGreeting()

  fun characterById(id: String): Character? = Characters.byId(id)

  fun selectedCharacter(): Character = repository.selectedCharacter()

  // --- Customization ---

  /** The base (un-customized) character for [id]. */
  fun baseCharacterById(id: String): Character? = repository.baseCharacter(id)

  /** The customized character for [id] (base merged with the saved override). */
  fun customizedCharacterById(id: String): Character? = repository.character(id)

  /** The saved customization for [id], or null. */
  fun overrideFor(id: String): CharacterOverride? = repository.overrideFor(id)

  /** Saves [override] for [id] (empty override is removed). */
  fun setOverride(id: String, override: CharacterOverride) = repository.setOverride(id, override)

  /** Restores [id] to its built-in defaults. */
  fun clearOverride(id: String) = repository.clearOverride(id)
}
