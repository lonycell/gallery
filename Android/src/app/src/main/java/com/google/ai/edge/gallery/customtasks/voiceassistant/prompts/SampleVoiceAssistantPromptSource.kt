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

import com.google.ai.edge.gallery.character.CharacterRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * An in-memory, sample-backed [VoiceAssistantPromptSource].
 *
 * This provides a small, curated set of topics so the feature works out of the box. It is designed
 * to be swapped out later for an implementation backed by a remote API or local storage — callers
 * depend only on the [VoiceAssistantPromptSource] interface.
 *
 * It also bridges the companion characters: when a character is selected (the default state of the
 * app), [getPromptForTopic] returns that character's persona as the system prompt so the on-device
 * LLM role-plays them. Curated topics remain available as a fallback.
 */
@Singleton
class SampleVoiceAssistantPromptSource
@Inject
constructor(private val characterRepository: CharacterRepository) : VoiceAssistantPromptSource {

  private val topics: List<TopicPrompt> =
    listOf(
      TopicPrompt(
        topicId = TopicPrompt.GENERAL_TOPIC_ID,
        title = "일반 어시스턴트",
        systemPrompt =
          "당신은 친절하고 간결한 한국어 음성 어시스턴트입니다. 답변은 음성으로 읽히므로 보통 한두 " +
            "문장으로 짧고 대화하듯 말하세요. 긴 목록, 코드 블록, 마크다운, 또는 소리내어 읽을 때 " +
            "어색한 특수문자는 사용하지 마세요. 질문이 모호하면 짧게 되물어 확인하세요. 항상 " +
            "한국어로 답하세요.",
        starters =
          listOf(
            "무엇을 도와줄 수 있어?",
            "흥미로운 사실 하나 알려줘.",
            "집중력을 높이는 간단한 팁을 알려줘.",
          ),
        bcp47Language = "ko-KR",
      ),
      TopicPrompt(
        topicId = "language_tutor",
        title = "언어 튜터",
        systemPrompt =
          "당신은 음성 대화를 진행하는 인내심 있는 언어 튜터입니다. 답변은 짧고 이해하기 쉽게 " +
            "유지하세요. 실수는 부드럽게 바로잡고 올바른 표현을 알려주며, 학습자가 계속 말하도록 " +
            "격려하세요. 답변은 음성으로 읽히므로 마크다운을 피하고 자연스러운 문장을 사용하세요. " +
            "항상 한국어로 답하세요.",
        starters =
          listOf(
            "간단한 대화를 연습해보자.",
            "정중하게 자기소개하는 법을 알려줘.",
            "내 문장을 그때그때 고쳐줘.",
          ),
        bcp47Language = "ko-KR",
      ),
      TopicPrompt(
        topicId = "interview_practice",
        title = "면접 연습",
        systemPrompt =
          "당신은 음성으로 모의 면접을 진행하는 면접 코치입니다. 한 번에 하나의 질문을 하고, 답변을 " +
            "기다린 뒤, 다음으로 넘어가기 전에 짧고 구체적인 피드백을 주세요. 음성으로 읽히므로 각 " +
            "차례는 짧게 유지하세요. 격려하되 솔직하게 말하세요. 항상 한국어로 답하세요.",
        starters =
          listOf(
            "소프트웨어 직무 모의 면접을 시작해줘.",
            "행동 면접 질문을 하나 해줘.",
            "'자기소개를 해보세요'에 어떻게 답하면 좋을까?",
          ),
        bcp47Language = "ko-KR",
      ),
      TopicPrompt(
        topicId = "travel_guide",
        title = "여행 가이드",
        systemPrompt =
          "당신은 음성으로 대화하는 활기찬 여행 가이드입니다. 간결하고 실용적인 제안을 주고 여행자의 " +
            "관심사를 물어보세요. 답변은 짧고 친근하게 말하며, 요청하지 않는 한 긴 일정은 나열하지 " +
            "말고 마크다운도 쓰지 마세요. 항상 한국어로 답하세요.",
        starters =
          listOf(
            "주말 여행 아이디어를 추천해줘.",
            "비 오는 도시에 갈 때 뭘 챙겨야 해?",
            "현지에서 먹어볼 만한 음식을 추천해줘.",
          ),
        bcp47Language = "ko-KR",
      ),
      TopicPrompt(
        topicId = "coding_helper",
        title = "코딩 도우미",
        systemPrompt =
          "당신은 음성 대화로 돕는 코딩 도우미입니다. 개념을 명확하고 간결하게, 쉬운 구어체로 " +
            "설명하세요. 답변이 음성으로 읽히므로 큰 코드 블록을 쏟아내지 말고 코드를 말로 설명하며, " +
            "사용자가 원하면 구체적인 내용을 풀어서 알려주겠다고 제안하세요. 답변은 짧게 유지하세요. " +
            "항상 한국어로 답하세요.",
        starters =
          listOf(
            "해시맵이 뭔지 설명해줘.",
            "리스트를 뒤집으려면 어떻게 해?",
            "스택과 큐의 차이가 뭐야?",
          ),
        bcp47Language = "ko-KR",
      ),
    )

  override suspend fun getPromptForTopic(topic: String?): TopicPrompt {
    // The app is character-centric: role-play the currently selected companion character.
    val character = characterRepository.selectedCharacter()
    return TopicPrompt(
      topicId = "character:${character.id}",
      title = character.name,
      systemPrompt = character.systemPrompt,
      starters = character.starters,
      bcp47Language = "ko-KR",
    )
  }

  /** Resolves a curated topic (kept for callers that pass an explicit topic string). */
  private fun resolveTopic(topic: String?): TopicPrompt {
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
        "당신은 친절하고 간결한 한국어 음성 어시스턴트입니다. 사용자가 제시한 다음 주제에 집중하세요: " +
          "\"$query\". 이 주제에서 벗어나지 말고, 대화를 통해 사용자가 이를 탐구하고 이해하거나 " +
          "해결하도록 도우세요. 답변은 음성으로 읽히므로 짧고 대화하듯 말하고, 마크다운과 특수문자를 " +
          "피하며, 필요하면 짧게 되물어 확인하세요. 항상 한국어로 답하세요.",
      starters =
        listOf(
          "$query 에 대해 간단히 알려줘.",
          "$query 는 어디서부터 시작하면 좋을까?",
          "$query 에서 흔히 하는 실수는 뭐야?",
        ),
      bcp47Language = "ko-KR",
    )
  }

  override suspend fun listTopics(): List<TopicPrompt> = topics

  private fun generalTopic(): TopicPrompt =
    topics.first { it.topicId == TopicPrompt.GENERAL_TOPIC_ID }
}
