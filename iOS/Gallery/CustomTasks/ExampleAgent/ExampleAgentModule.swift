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

// Port of customtasks/exampleagent/ExampleAgentModule.kt
//
// TEMPLATE: registration module for the ExampleAgent task.
//
// This task is a template, so registration is DISABLED by default to keep
// it off the home screen. To enable it, call `ExampleAgentModule.make()` and
// append the result inside `BuiltInTasks.makeAll()` or
// `FeatureTaskModules.registered()`. Mirrors the commented-out Hilt
// `@Provides @IntoSet fun provideTask()` on Android.

import Foundation

enum ExampleAgentModule {
    /// Factory matching the Hilt `@Provides @IntoSet` pattern.
    /// DISABLED by default (template module). Uncomment the call-site in
    /// BuiltInTasks / FeatureTaskModules to activate on the home screen.
    static func make() -> CustomTask {
        return ExampleAgentTask()
    }
}
