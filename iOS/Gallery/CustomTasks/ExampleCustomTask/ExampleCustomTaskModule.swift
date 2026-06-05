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

// Port of customtasks/examplecustomtask/ExampleCustomTaskModule.kt
//
// Android used Hilt @Module / @Provides @IntoSet with the function commented out
// by default. On iOS the integrator calls `ExampleCustomTaskModule.make()` and
// appends it to BuiltInTasks / FeatureTaskModules. Currently DISABLED by default.

import Foundation

enum ExampleCustomTaskModule {
    /// Factory matching the Hilt `@Provides @IntoSet` pattern.
    /// DISABLED by default. Uncomment the call-site in BuiltInTasks /
    /// FeatureTaskModules to display the task on the home screen.
    static func make() -> CustomTask {
        return ExampleCustomTask()
    }
}
