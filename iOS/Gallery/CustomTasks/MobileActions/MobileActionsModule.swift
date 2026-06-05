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

// Port of customtasks/mobileactions/MobileActionsModule.kt
//
// Android used Hilt @Module / @Provides @IntoSet to contribute the task to the
// app's Set<CustomTask>. On iOS the integrator calls `MobileActionsModule.make()`
// and appends the result to the custom task registry in BuiltInTasks / AppContainer.

import Foundation

enum MobileActionsModule {
    /// Factory matching the Hilt `@Provides @IntoSet` pattern.
    /// Wire into `BuiltInTasks.makeAll()` / `FeatureTaskModules.registered()`.
    static func make() -> CustomTask {
        return MobileActionsTask()
    }
}
