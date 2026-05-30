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

package com.google.ai.edge.gallery.customtasks.voiceassistant.prompts

/**
 * Supplies the system prompts / topic metadata used by the Voice Assistant.
 *
 * This is intentionally an interface so the source of prompts can evolve over time. Today it is
 * backed by an in-memory sample ([SampleVoiceAssistantPromptSource]), but a future implementation
 * could fetch prompts from a remote API or read them from local storage (DataStore, a bundled
 * asset, a downloaded prompt pack, etc.) without changing any caller.
 */
interface VoiceAssistantPromptSource {
  /**
   * Returns the prompt bundle to use for the given [topic].
   *
   * @param topic A free-form topic or problem string supplied as an entry parameter, or `null` to
   *   get the default general-purpose assistant. Implementations should always return a usable
   *   [TopicPrompt]: when [topic] doesn't match a known/curated topic, they should fall back to a
   *   generic prompt that still incorporates the raw [topic] text so an arbitrary subject can be
   *   discussed.
   */
  suspend fun getPromptForTopic(topic: String?): TopicPrompt

  /** Returns the list of curated topics that can be offered to the user. */
  suspend fun listTopics(): List<TopicPrompt>
}
