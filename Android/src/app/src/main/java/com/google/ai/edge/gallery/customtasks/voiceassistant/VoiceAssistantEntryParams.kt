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

package com.google.ai.edge.gallery.customtasks.voiceassistant

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Holds the optional entry "topic"/"problem" parameter for the Voice Assistant.
 *
 * The Voice Assistant can be opened either:
 * - from the home-screen task card, in which case no topic is set (general assistant), or
 * - programmatically (e.g. from a deep link, an intent, or another screen) that wants the assistant
 *   to focus on a specific subject. Such callers should call [setTopic] BEFORE navigating into the
 *   task, and the task will pick it up during model initialization.
 *
 * A process-wide singleton is used (rather than nav arguments) because custom tasks are launched
 * through the shared CustomTask framework, which doesn't thread per-task parameters through. The
 * topic is consumed once so it doesn't leak into a later, unrelated launch.
 */
@Singleton
class VoiceAssistantEntryParams @Inject constructor() {
  private val _topic = MutableStateFlow<String?>(null)
  val topic = _topic.asStateFlow()

  /** Sets the topic/problem to focus the next Voice Assistant session on. */
  fun setTopic(topic: String?) {
    _topic.value = topic?.trim()?.ifEmpty { null }
  }

  /** Returns the current topic and clears it so it is only applied once. */
  fun consumeTopic(): String? {
    val current = _topic.value
    _topic.value = null
    return current
  }
}
