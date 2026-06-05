/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of di/AppModule.kt (+ GalleryApplication.onCreate)
//
// Hilt's SingletonComponent provided the repositories and serializers. iOS uses a
// single `AppContainer` ObservableObject built once at launch and injected into the
// SwiftUI environment, holding the same singletons and the registered custom tasks.

import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppContainer: ObservableObject {
  // Repositories (Hilt @Provides @Singleton equivalents).
  let dataStoreRepository: DataStoreRepository
  let downloadRepository: DownloadRepository
  let systemPromptRepository: SystemPromptRepository
  let notificationScheduleManager: NotificationScheduleManager
  let notificationActionHandler: NotificationActionHandler
  let llmModelHelper: LlmModelHelper

  /// Companion-character store (shared by the voice graph). Mirrors CharacterRepository.
  let characterRepository: CharacterRepository

  /// The central app state, shared across the whole navigation graph.
  let modelManagerViewModel: ModelManagerViewModel

  /// Drives the root NavigationStack (NavHostController equivalent).
  let router = Router()

  init() {
    let store = DefaultDataStoreRepository()
    let download = DefaultDownloadRepository()
    let prompts = SystemPromptRepository(store: store)
    let helper = StubLlmModelHelper()
    let scheduleManager = NotificationScheduleManager(store: store)
    let charRepo = CharacterRepository()

    self.dataStoreRepository = store
    self.downloadRepository = download
    self.systemPromptRepository = prompts
    self.llmModelHelper = helper
    self.notificationScheduleManager = scheduleManager
    self.characterRepository = charRepo
    self.notificationActionHandler = NotificationActionHandler(scheduleManager: scheduleManager)

    // Shared statics used by the function-calling custom tasks (MobileActions,
    // TinyGarden, ExampleAgent) — they reach the runtime/store through these.
    AppContainer.sharedLlmHelper = helper
    AppContainer.sharedDataStore = store

    // Build the custom-task set (Hilt @IntoSet). Order = home-screen tile order.
    let agentChatTask = AgentChatTaskModule.make()
    (agentChatTask as? AgentChatTask)?.setDataStoreRepository(store)
    IntentHandler.notificationManager = scheduleManager

    var tasks: [CustomTask] = []
    tasks.append(LlmChatTaskModule.makeChat(llmModelHelper: helper))
    tasks.append(LlmChatTaskModule.makeAskImage(llmModelHelper: helper))
    tasks.append(LlmChatTaskModule.makeAskAudio(llmModelHelper: helper))
    tasks.append(LlmSingleTurnTaskModule.make(llmModelHelper: helper))
    tasks.append(agentChatTask)
    tasks.append(MobileActionsModule.make())
    tasks.append(TinyGardenTaskModule.make())
    tasks.append(TtsModule.make())
    tasks.append(SttModule.make())
    tasks.append(VoiceAssistantModule.make(characterRepository: charRepo))
    // Example/template tasks stay disabled by default (mirroring the commented-out
    // Hilt modules): ExampleAgentModule.make(), ExampleCustomTaskModule.make().

    self.modelManagerViewModel = ModelManagerViewModel(
      dataStoreRepository: store,
      downloadRepository: download,
      systemPromptRepository: prompts,
      llmModelHelper: helper,
      customTasks: tasks)

    // GalleryApplication.onCreate equivalents.
    scheduleManager.initialize()
    ThemeSettings.shared.themeOverride = store.readTheme()

    // Notification tap routing (FCM/local) -> deep-link handling.
    let mm = modelManagerViewModel
    let rt = router
    notificationActionHandler.deepLinkHandler = { url in
      Task { @MainActor in rt.handleDeepLink(url, modelManager: mm) }
    }
    UNUserNotificationCenter.current().delegate = notificationActionHandler
  }
}
