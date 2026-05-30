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
 * A prompt bundle describing how the Voice Assistant should behave for a given topic.
 *
 * @param topicId A stable identifier for the topic (e.g. "general", "language_tutor"). The special
 *   value [GENERAL_TOPIC_ID] represents the default, no-topic assistant.
 * @param title A short, human-readable title shown in the UI (e.g. "Language Tutor").
 * @param systemPrompt The system instruction that primes the LLM for this topic.
 * @param starters A few suggested opening utterances the user can tap to start the conversation.
 * @param bcp47Language Optional BCP-47 tag (e.g. "en-US", "ko-KR") hinting which language the
 *   assistant should speak/recognize for this topic. Null means use the device default.
 */
data class TopicPrompt(
  val topicId: String,
  val title: String,
  val systemPrompt: String,
  val starters: List<String> = listOf(),
  val bcp47Language: String? = null,
) {
  companion object {
    const val GENERAL_TOPIC_ID = "general"
  }
}
