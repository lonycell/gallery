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

import com.google.ai.edge.gallery.customtasks.common.CustomTask
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.SampleVoiceAssistantPromptSource
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.VoiceAssistantPromptSource
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet

/**
 * Binds the [VoiceAssistantPromptSource] interface to its current implementation.
 *
 * Swapping the prompt source later (e.g. for an API- or storage-backed one) only requires changing
 * this binding.
 */
@Module
@InstallIn(SingletonComponent::class)
internal abstract class VoiceAssistantBindingsModule {
  @Binds
  abstract fun bindPromptSource(
    impl: SampleVoiceAssistantPromptSource
  ): VoiceAssistantPromptSource
}

/** Contributes the Voice Assistant task into the app's set of custom tasks. */
@Module
@InstallIn(SingletonComponent::class)
internal object VoiceAssistantModule {
  @Provides
  @IntoSet
  fun provideTask(
    promptSource: VoiceAssistantPromptSource,
    entryParams: VoiceAssistantEntryParams,
    characterRepository: com.google.ai.edge.gallery.character.CharacterRepository,
    chatHistoryStore: ChatHistoryStore,
  ): CustomTask {
    return VoiceAssistantTask(
      promptSource = promptSource,
      entryParams = entryParams,
      characterRepository = characterRepository,
      chatHistoryStore = chatHistoryStore,
    )
  }
}
