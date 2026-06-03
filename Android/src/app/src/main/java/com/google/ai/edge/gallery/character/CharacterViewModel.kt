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

  val characters: List<Character> = repository.characters
  val state: StateFlow<CharacterState> = repository.state

  fun isUnlocked(character: Character): Boolean = repository.isUnlocked(character)

  fun select(id: String) = repository.select(id)

  fun tryUnlockWithCoins(character: Character): Boolean = repository.tryUnlockWithCoins(character)

  fun subscribe() = repository.subscribe()

  fun characterById(id: String): Character? = Characters.byId(id)

  fun selectedCharacter(): Character = repository.selectedCharacter()
}
