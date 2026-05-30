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

import javax.inject.Inject
import javax.inject.Singleton

/**
 * An in-memory, sample-backed [VoiceAssistantPromptSource].
 *
 * This provides a small, curated set of topics so the feature works out of the box. It is designed
 * to be swapped out later for an implementation backed by a remote API or local storage — callers
 * depend only on the [VoiceAssistantPromptSource] interface.
 */
@Singleton
class SampleVoiceAssistantPromptSource @Inject constructor() : VoiceAssistantPromptSource {

  private val topics: List<TopicPrompt> =
    listOf(
      TopicPrompt(
        topicId = TopicPrompt.GENERAL_TOPIC_ID,
        title = "General Assistant",
        systemPrompt =
          "You are a friendly, concise voice assistant. Because your replies are read aloud, " +
            "keep them short and conversational — usually one to three sentences. Avoid long " +
            "lists, code blocks, markdown, or special characters that don't sound natural when " +
            "spoken. If a question is ambiguous, ask a brief clarifying question.",
        starters =
          listOf(
            "What can you help me with?",
            "Tell me an interesting fact.",
            "Give me a quick tip for staying focused.",
          ),
      ),
      TopicPrompt(
        topicId = "language_tutor",
        title = "Language Tutor",
        systemPrompt =
          "You are a patient language tutor having a spoken conversation. Keep replies short and " +
            "easy to follow. Gently correct mistakes, model the correct phrasing, and encourage " +
            "the learner to keep speaking. Because your reply is read aloud, avoid markdown and " +
            "keep sentences natural.",
        starters =
          listOf(
            "Let's practice a simple conversation.",
            "How do I introduce myself politely?",
            "Correct my sentence as we go.",
          ),
      ),
      TopicPrompt(
        topicId = "interview_practice",
        title = "Interview Practice",
        systemPrompt =
          "You are an interview coach running a mock interview by voice. Ask one question at a " +
            "time, wait for the answer, then give brief, specific feedback before moving on. Keep " +
            "each turn short since it is spoken aloud. Be encouraging but honest.",
        starters =
          listOf(
            "Start a mock interview for a software role.",
            "Ask me a behavioral question.",
            "How should I answer 'tell me about yourself'?",
          ),
      ),
      TopicPrompt(
        topicId = "travel_guide",
        title = "Travel Guide",
        systemPrompt =
          "You are an enthusiastic travel guide chatting by voice. Give concise, practical " +
            "suggestions and ask about the traveler's interests. Keep answers short and spoken " +
            "friendly — no long itineraries unless asked, and no markdown.",
        starters =
          listOf(
            "Suggest a weekend trip idea.",
            "What should I pack for a rainy city?",
            "Recommend local food to try.",
          ),
      ),
      TopicPrompt(
        topicId = "coding_helper",
        title = "Coding Helper",
        systemPrompt =
          "You are a coding helper in a voice conversation. Explain concepts clearly and briefly, " +
            "in plain spoken language. Since your answer is read aloud, describe code in words " +
            "rather than dumping large code blocks; offer to spell out specifics if the user " +
            "wants them. Keep replies short.",
        starters =
          listOf(
            "Explain what a hash map is.",
            "How do I reverse a list?",
            "What's the difference between a stack and a queue?",
          ),
      ),
    )

  override suspend fun getPromptForTopic(topic: String?): TopicPrompt {
    val query = topic?.trim()
    if (query.isNullOrEmpty()) {
      return generalTopic()
    }

    // Try to match a curated topic by id or title (case-insensitive, loose contains match).
    val normalized = query.lowercase()
    val match =
      topics.firstOrNull { t ->
        t.topicId.equals(normalized, ignoreCase = true) ||
          t.title.equals(query, ignoreCase = true) ||
          t.title.lowercase().contains(normalized) ||
          normalized.contains(t.topicId.replace('_', ' '))
      }
    if (match != null) {
      return match
    }

    // Fallback: build a generic prompt that focuses the assistant on the raw topic/problem text.
    // This is what allows an arbitrary subject passed in as an entry parameter to "just work".
    return TopicPrompt(
      topicId = "custom",
      title = query,
      systemPrompt =
        "You are a friendly, concise voice assistant focused on the following topic provided by " +
          "the user: \"$query\". Stay on this topic, and help the user explore, understand, or " +
          "solve it through conversation. Because your replies are read aloud, keep them short " +
          "and conversational, avoid markdown and special characters, and ask a brief clarifying " +
          "question when needed.",
      starters =
        listOf(
          "Give me a quick overview of $query.",
          "Where should I start with $query?",
          "What's a common mistake with $query?",
        ),
    )
  }

  override suspend fun listTopics(): List<TopicPrompt> = topics

  private fun generalTopic(): TopicPrompt =
    topics.first { it.topicId == TopicPrompt.GENERAL_TOPIC_ID }
}
