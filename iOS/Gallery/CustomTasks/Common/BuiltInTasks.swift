/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Central registry that instantiates every built-in / custom task, mirroring the
// per-feature Hilt modules (`LlmChatTaskModule`, `AgentChatTaskModule`,
// `MobileActionsModule`, `TinyGardenTaskModule`, `SttModule`, `TtsModule`,
// `ExampleAgentModule`, `ExampleCustomTaskModule`) that each bound a
// `@Provides @IntoSet CustomTask`. Each feature module defines a factory and is
// wired in here during integration.

import Foundation

enum BuiltInTasks {
  static func makeAll() -> [CustomTask] {
    var tasks: [CustomTask] = []
    // Feature task modules are appended here once their factories exist, e.g.:
    //   tasks.append(LlmChatTaskModule.makeChat())
    //   tasks.append(LlmChatTaskModule.makeAskImage())
    //   tasks.append(LlmChatTaskModule.makeAskAudio())
    //   tasks.append(LlmSingleTurnTaskModule.make())
    //   tasks.append(AgentChatTaskModule.make())
    //   tasks.append(MobileActionsModule.make())
    //   tasks.append(TinyGardenTaskModule.make())
    //   tasks.append(SttModule.make())
    //   tasks.append(TtsModule.make())
    //   tasks.append(ExampleAgentModule.make())
    //   tasks.append(ExampleCustomTaskModule.make())
    tasks.append(contentsOf: FeatureTaskModules.registered())
    return tasks
  }
}

/// Feature modules contribute their tasks by extending this type's `registered()`
/// during integration, keeping each module self-contained like its Hilt module.
enum FeatureTaskModules {
  static func registered() -> [CustomTask] { [] }
}
