/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/navigation/GalleryNavGraph.kt — the NavHost.
//
// The start destination is the voice graph's MainPage (Android:
// startDestination = ROUTE_VOICE_GRAPH -> ROUTE_MAINPAGE). MainPage,
// VoiceChatSettingsScreen and CharacterScreen share a single
// VoiceAssistantViewModel + CharacterViewModel scoped to this view (the nested
// `voice_graph` shared-back-stack-entry behavior on Android). All other routes
// (home, model list, model detail, model manager, benchmark, notifications,
// subscription) are pushed onto the NavigationStack.

import SwiftUI

struct GalleryNavHost: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  @EnvironmentObject private var router: Router
  let container: AppContainer

  // Voice-graph-scoped shared view models.
  @StateObject private var voiceVM: VoiceAssistantViewModel
  @StateObject private var characterVM: CharacterViewModel

  init(container: AppContainer) {
    self.container = container
    self.modelManagerViewModel = container.modelManagerViewModel
    let charRepo = container.characterRepository
    let promptSource = SampleVoiceAssistantPromptSource(characterRepository: charRepo)
    _voiceVM = StateObject(wrappedValue: VoiceAssistantViewModel(
      promptSource: promptSource,
      entryParams: VoiceAssistantEntryParams(),
      chatHistoryStore: ChatHistoryStore(),
      characterRepository: charRepo))
    _characterVM = StateObject(wrappedValue: CharacterViewModel(repository: charRepo))
  }

  var body: some View {
    NavigationStack(path: $router.path) {
      MainPage(
        modelManagerViewModel: modelManagerViewModel,
        viewModel: voiceVM,
        characterViewModel: characterVM,
        onOpenSettings: { router.navigate(.voiceSettings) },
        onOpenCharacters: { router.navigate(.characters) })
      .navigationBarBackButtonHidden(true)
      .navigationDestination(for: Route.self) { route in
        destination(for: route)
      }
    }
  }

  @ViewBuilder
  private func destination(for route: Route) -> some View {
    switch route {
    case .mainPage:
      MainPage(modelManagerViewModel: modelManagerViewModel, viewModel: voiceVM,
               characterViewModel: characterVM,
               onOpenSettings: { router.navigate(.voiceSettings) },
               onOpenCharacters: { router.navigate(.characters) })

    case .voiceSettings:
      VoiceChatSettingsScreen(
        modelManagerViewModel: modelManagerViewModel, viewModel: voiceVM,
        characterViewModel: characterVM,
        onOpenSubscription: { router.navigate(.subscription) },
        navigateUp: { router.navigateUp() })
      .navigationBarBackButtonHidden(true)

    case .characters:
      CharacterScreen(
        viewModel: characterVM,
        availableVoices: voiceVM.uiState.voices,
        onStartChat: { router.popTo(.mainPage, inclusive: false) },
        onOpenSubscription: { router.navigate(.subscription) },
        navigateUp: { router.navigateUp() })
      .navigationBarBackButtonHidden(true)

    case .subscription:
      SubscriptPage(onClose: { router.navigateUp() },
                    onPurchase: { characterVM.subscribe() })
      .navigationBarBackButtonHidden(true)

    case .home:
      HomeScreen(modelManagerViewModel: modelManagerViewModel, gm4: true)

    case .modelList(let taskId):
      if let task = modelManagerViewModel.getTaskById(taskId) {
        ModelManager(
          task: task,
          viewModel: modelManagerViewModel,
          navigateUp: { router.navigateUp() },
          onModelClicked: { model in router.navigate(.model(taskId: task.id, modelName: model.name)) },
          onBenchmarkClicked: { model in router.navigate(.benchmark(modelName: model.name)) })
        .navigationBarBackButtonHidden(true)
      }

    case .model(let taskId, let modelName, let query):
      ModelRouteView(modelManagerViewModel: modelManagerViewModel,
                     taskId: taskId, modelName: modelName, query: query)
        .navigationBarBackButtonHidden(true)

    case .modelManager:
      GlobalModelManager(
        viewModel: modelManagerViewModel,
        navigateUp: { router.navigateUp() },
        onModelSelected: { task, model in router.navigate(.model(taskId: task.id, modelName: model.name)) },
        onBenchmarkClicked: { model in router.navigate(.benchmark(modelName: model.name)) })
      .navigationBarBackButtonHidden(true)

    case .notifications:
      NotificationsScreen(
        viewModel: NotificationsViewModel(scheduleManager: container.notificationScheduleManager),
        navigateUp: { router.navigateUp() })
      .navigationBarBackButtonHidden(true)

    case .benchmark(let modelName):
      if let model = modelManagerViewModel.getModelByName(modelName) {
        BenchmarkScreen(initialModel: model, modelManagerViewModel: modelManagerViewModel,
                        onBackClicked: { router.navigateUp() })
        .navigationBarBackButtonHidden(true)
      }
    }
  }
}

/// Renders a task's model detail screen. Mirrors the ROUTE_MODEL branch +
/// `CustomTaskScreen` wrapper in GalleryNavGraph.kt: legacy built-in tasks get a
/// `CustomTaskDataForBuiltinTask`; other custom tasks get a `CustomTaskData`.
struct ModelRouteView: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let taskId: String
  let modelName: String
  let query: String?
  @EnvironmentObject private var router: Router

  var body: some View {
    Group {
      if let model = modelManagerViewModel.getModelByName(modelName),
         let custom = modelManagerViewModel.getCustomTaskByTaskId(taskId) {
        if isLegacyTasks(taskId) {
          custom.mainScreen(data: CustomTaskDataForBuiltinTask(
            modelManagerViewModel: modelManagerViewModel,
            onNavUp: { router.navigateUp() },
            initialQuery: query))
        } else {
          custom.mainScreen(data: CustomTaskData(
            modelManagerViewModel: modelManagerViewModel,
            setCustomNavigateUpCallback: { _ in }))
            .onAppear {
              modelManagerViewModel.selectModel(model)
              if modelManagerViewModel.isModelDownloaded(model) {
                modelManagerViewModel.initializeModel(task: custom.task, model: model)
              }
            }
        }
      } else {
        VStack { Text("Model not found").font(AppTypography.bodyLarge) }
      }
    }
    .onAppear {
      if let model = modelManagerViewModel.getModelByName(modelName) {
        modelManagerViewModel.selectModel(model)
      }
    }
  }
}
