// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/VoiceAssistantTask.kt

import SwiftUI

/// The task id of the Voice Assistant. Shared with the model manager so the same
/// downloadable LLMs offered for chat are also available here.
let VOICE_ASSISTANT_TASK_ID = "speech_voice_assistant"

/// Constants matching the Android speech model names (shared with Speech tasks).
let NEURAL_STT_MODEL_NAME      = "SenseVoice Small (ko)"
let WHISPER_KO_STT_MODEL_NAME  = "Whisper Small (ko)"

/// A custom task that hosts the hands-free Voice Assistant.
///
/// The user speaks (SFSpeechRecognizer or optional neural recognizer), the on-device
/// LLM replies through `LlmModelHelper`, the reply is shown on screen as it streams in,
/// and simultaneously read aloud (AVSpeechSynthesizer or an optional neural voice).
///
/// The Voice Assistant shares the same downloadable chat LLMs offered for `llm_chat`:
/// the model manager populates `task.models` with every LLM from the allowlist.
final class VoiceAssistantTask: CustomTask {

    let task: Task

    // Shared tool / skill / MCP surface.
    // NOTE: AgentTools is not yet ported to iOS. Replace the Any? placeholder with the
    // real AgentTools type when the AgentChat module is available.
    var agentTools: Any? = nil

    private let promptSource: VoiceAssistantPromptSource
    private let entryParams: VoiceAssistantEntryParams
    private let characterRepository: CharacterRepository
    private let chatHistoryStore: ChatHistoryStore

    init(promptSource: VoiceAssistantPromptSource,
         entryParams: VoiceAssistantEntryParams,
         characterRepository: CharacterRepository,
         chatHistoryStore: ChatHistoryStore) {
        self.promptSource = promptSource
        self.entryParams = entryParams
        self.characterRepository = characterRepository
        self.chatHistoryStore = chatHistoryStore
        self.task = Task(
            id: VOICE_ASSISTANT_TASK_ID,
            label: "음성 어시스턴트",
            category: SpeechCategory,
            icon: .system("waveform"),
            description:
                "온디바이스 AI와 손을 쓰지 않고 음성으로 대화하세요. 자연스럽게 말하면 답변이 실시간으로 " +
                "화면에 나타나고 동시에 음성으로 읽어줍니다.",
            shortDescription: "음성으로 AI와 대화",
            sourceCodeUrl:
                "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/voiceassistant",
            newFeature: true,
            models: []
        )
    }

    func initializeModelFn(model: Model, systemInstruction: Contents?,
                           onDone: @escaping (String) -> Void) {
        Task {
            // Resolve the entry topic into a system prompt.
            let topic = await self.entryParams.topic
            let prompt = await self.promptSource.getPromptForTopic(topic)
            let basePrompt = prompt.systemPrompt

            // Build the KakaoTalk + web-search augmented system prompt.
            // NOTE: KakaoShareTools and WebSearchTools are not yet ported to iOS.
            // When they are, add their instruction text here and pass real ToolProviders
            // to the initializer.
            var finalPrompt = basePrompt
            if !finalPrompt.isEmpty { finalPrompt += "\n\n" }
            finalPrompt +=
                "사용자가 카카오톡(카톡) 메시지를 보내달라고 명확히 말하면 `sendKakaoMessage` 도구를 " +
                "호출하세요. 보내기 전에 수신자와 메시지 내용을 사용자에게 요약해 확인받으세요."
            finalPrompt += "\n\n"
            finalPrompt +=
                "최신 뉴스·오늘의 사실·시세·일정처럼 시의성이 있거나 당신이 확실히 알지 못하는 정보가 " +
                "필요하면, 말로 설명하기 전에 먼저 `searchWeb` 도구를 실제로 호출하세요."

            let instruction: Contents? = finalPrompt.isEmpty ? nil : finalPrompt

            // Restore this character's prior conversation so the LLM "remembers" the chat.
            let history = self.chatHistoryStore.load(self.characterRepository.selectedCharacter().id)
                .map { msg -> LlmMessage in
                    LlmMessage(role: msg.role == .user ? .user : .model, text: msg.text)
                }

            // NOTE: Real inference initialization is a stub until LiteRT-LM / MediaPipe
            // is available. `StubLlmModelHelper` completes immediately.
            StubLlmModelHelper().initialize(
                model: model,
                taskId: VOICE_ASSISTANT_TASK_ID,
                supportImage: false,
                supportAudio: false,
                systemInstruction: instruction,
                tools: [],
                enableConversationConstrainedDecoding: true,
                initialMessages: history,
                onDone: onDone
            )
        }
    }

    func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
        StubLlmModelHelper().cleanUp(model: model, onDone: onDone)
    }

    @MainActor func mainScreen(data: Any) -> AnyView {
        // VoiceAssistantScreen is the standalone task screen (not the MainPage companion UI).
        // The MainPage companion experience is wired separately via VoiceAssistantModule.make().
        guard let taskData = data as? CustomTaskData else { return AnyView(EmptyView()) }
        return AnyView(
            VoiceAssistantScreen(
                task: task,
                modelManagerViewModel: taskData.modelManagerViewModel
            )
        )
    }
}
