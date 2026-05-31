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
package com.google.ai.edge.gallery.customtasks.exampleagent

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * TEMPLATE: the Hilt module that registers the example agent with the app.
 *
 * This task is a template, so the registration is DISABLED by default (the provider is commented
 * out) to keep it off the home screen. To try it in the app, uncomment the imports and the
 * `provideTask` function below — `@Provides @IntoSet` adds the task to the app's `Set<CustomTask>`,
 * which the home screen discovers automatically (no other wiring needed).
 *
 * This mirrors how every real task is registered, e.g. `MobileActionsModule` /
 * `customtasks/examplecustomtask/ExampleCustomTaskModule`.
 *
 * If your task has constructor dependencies, inject them as parameters of `provideTask(...)` (see
 * `customtasks/voiceassistant/VoiceAssistantModule` for an example that injects collaborators, and
 * a `@Binds` interface binding).
 */
@Module
@InstallIn(SingletonComponent::class)
internal object ExampleAgentModule {
  /* Uncomment to enable this template task in the app.
  @dagger.Provides
  @dagger.multibindings.IntoSet
  fun provideTask(): com.google.ai.edge.gallery.customtasks.common.CustomTask {
    return ExampleAgentTask()
  }
  */
}
