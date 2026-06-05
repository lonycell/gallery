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

// Port of customtasks/examplecustomtask/ExampleCustomTaskViewModel.kt

import SwiftUI

/// UI state for the example custom task. Mirrors `ExampleCustomTaskUiState`.
struct ExampleCustomTaskUiState {
    var textColor: Color = .primary
}

/// ViewModel for the example custom task. Mirrors `ExampleCustomTaskViewModel`.
@MainActor
final class ExampleCustomTaskViewModel: ObservableObject {
    @Published var uiState = ExampleCustomTaskUiState()

    func updateTextColor(color: Color) {
        uiState.textColor = color
    }
}
