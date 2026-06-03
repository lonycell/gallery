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

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Number of bonus coins granted when the user (simulated-)subscribes to Pro. */
const val SUBSCRIBE_BONUS_COINS = 600

/** Coins granted on first launch so the coin-unlock flow is usable without subscribing. */
const val WELCOME_COINS = 300

/**
 * Persisted ownership/economy state for the companion characters.
 *
 * @param coins the user's coin balance.
 * @param unlockedIds character ids the user has unlocked by spending coins.
 * @param selectedId the currently active character.
 * @param isPro whether the user has the (simulated) Pro subscription, which unlocks every character
 *   and is meant to gate other premium behaviour across the app.
 */
data class CharacterState(
  val coins: Int = 0,
  val unlockedIds: Set<String> = emptySet(),
  val selectedId: String = "",
  val isPro: Boolean = false,
  /** Per-character TTS voice id (e.g. "neural:kss", "neural:melo", "system:<name>"). */
  val voiceByCharacter: Map<String, String> = emptyMap(),
)

/**
 * Single source of truth for character ownership, the coin balance and the Pro flag.
 *
 * State is persisted with [android.content.SharedPreferences] (kept independent of the protobuf
 * settings store) and exposed as a [StateFlow] so any screen reacts to changes. Purchases and the
 * subscription are simulated here today, but the resulting flags are stored durably so other
 * screens can branch on them (e.g. unlock-gating, Pro-only features) and a real billing backend can
 * be wired in later without changing callers.
 */
@Singleton
class CharacterRepository @Inject constructor(@ApplicationContext context: Context) {

  val characters: List<Character> = Characters.all

  private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  private val _state = MutableStateFlow(load())
  val state: StateFlow<CharacterState> = _state.asStateFlow()

  private fun load(): CharacterState {
    val defaultSelected = characters.firstOrNull()?.id ?: ""
    return CharacterState(
      coins = prefs.getInt(KEY_COINS, WELCOME_COINS),
      unlockedIds = prefs.getStringSet(KEY_UNLOCKED, emptySet())?.toSet() ?: emptySet(),
      selectedId = prefs.getString(KEY_SELECTED, defaultSelected) ?: defaultSelected,
      isPro = prefs.getBoolean(KEY_PRO, false),
      voiceByCharacter = decodeVoices(prefs.getStringSet(KEY_VOICES, emptySet())),
    )
  }

  private fun persist(newState: CharacterState) {
    prefs
      .edit()
      .putInt(KEY_COINS, newState.coins)
      .putStringSet(KEY_UNLOCKED, newState.unlockedIds)
      .putString(KEY_SELECTED, newState.selectedId)
      .putBoolean(KEY_PRO, newState.isPro)
      .putStringSet(KEY_VOICES, encodeVoices(newState.voiceByCharacter))
      .apply()
    _state.value = newState
  }

  // Voices are stored as a string set of "characterId=voiceId" entries (voice ids never contain '=').
  private fun decodeVoices(raw: Set<String>?): Map<String, String> =
    raw
      ?.mapNotNull { entry ->
        val idx = entry.indexOf('=')
        if (idx <= 0) null else entry.substring(0, idx) to entry.substring(idx + 1)
      }
      ?.toMap() ?: emptyMap()

  private fun encodeVoices(map: Map<String, String>): Set<String> =
    map.entries.map { "${it.key}=${it.value}" }.toSet()

  /** Assigns the TTS voice [voiceId] to [characterId]. */
  fun setVoiceForCharacter(characterId: String, voiceId: String) {
    val updated = _state.value.voiceByCharacter.toMutableMap().apply { put(characterId, voiceId) }
    persist(_state.value.copy(voiceByCharacter = updated))
  }

  /** The voice assigned to [characterId], or an empty string if none has been chosen. */
  fun voiceForCharacter(characterId: String): String =
    _state.value.voiceByCharacter[characterId] ?: ""

  /** Whether [character] is available to use (free, already purchased, or unlocked by Pro). */
  fun isUnlocked(character: Character): Boolean {
    val s = _state.value
    return character.freeByDefault || s.isPro || s.unlockedIds.contains(character.id)
  }

  fun isUnlocked(id: String): Boolean = Characters.byId(id)?.let { isUnlocked(it) } ?: false

  /** The currently selected character (falls back to the first one). */
  fun selectedCharacter(): Character =
    Characters.byId(_state.value.selectedId) ?: characters.first()

  /** Selects [id] as the active character if it is unlocked. */
  fun select(id: String) {
    val character = Characters.byId(id) ?: return
    if (isUnlocked(character) && _state.value.selectedId != id) {
      persist(_state.value.copy(selectedId = id))
    }
  }

  /**
   * Attempts to unlock [character] by spending coins. Returns true if it is now unlocked (either it
   * already was, or the purchase succeeded), false if the user doesn't have enough coins.
   */
  fun tryUnlockWithCoins(character: Character): Boolean {
    if (isUnlocked(character)) return true
    val s = _state.value
    if (s.coins < character.priceCoins) return false
    persist(
      s.copy(coins = s.coins - character.priceCoins, unlockedIds = s.unlockedIds + character.id)
    )
    return true
  }

  /** Adds coins to the balance (e.g. a reward). */
  fun addCoins(amount: Int) {
    if (amount == 0) return
    persist(_state.value.copy(coins = _state.value.coins + amount))
  }

  /** Simulates a successful Pro subscription: sets the flag and grants bonus coins. */
  fun subscribe() {
    val s = _state.value
    persist(s.copy(isPro = true, coins = s.coins + SUBSCRIBE_BONUS_COINS))
  }

  private companion object {
    const val PREFS_NAME = "character_store"
    const val KEY_COINS = "coins"
    const val KEY_UNLOCKED = "unlocked_ids"
    const val KEY_SELECTED = "selected_id"
    const val KEY_PRO = "is_pro"
    const val KEY_VOICES = "voice_by_character"
  }
}
