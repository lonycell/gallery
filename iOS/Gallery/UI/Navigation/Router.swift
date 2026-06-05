/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Routing primitives for ui/navigation/GalleryNavGraph.kt.
//
// Compose used a NavHost with string routes and a nested `voice_graph`. SwiftUI
// uses a NavigationStack driven by this typed `Route` enum and a `Router`
// ObservableObject. The route names map 1:1 to the Android route constants.

import SwiftUI

/// Mirrors the ROUTE_* string constants in GalleryNavGraph.kt.
enum Route: Hashable {
  case mainPage                              // ROUTE_MAINPAGE (start of voice_graph)
  case voiceSettings                         // ROUTE_VOICE_SETTINGS
  case characters                            // ROUTE_CHARACTERS
  case subscription                          // ROUTE_SUBSCRIPTION
  case home                                  // ROUTE_HOMESCREEN
  case modelList(taskId: String)             // ROUTE_MODEL_LIST (task picked)
  case model(taskId: String, modelName: String, query: String? = nil)  // ROUTE_MODEL
  case modelManager                          // ROUTE_MODEL_MANAGER
  case notifications                         // ROUTE_NOTIFICATIONS
  case benchmark(modelName: String)          // ROUTE_BENCHMARK
}

/// Drives the NavigationStack. Mirrors the NavHostController usage.
@MainActor
final class Router: ObservableObject {
  @Published var path: [Route] = []

  func navigate(_ route: Route) { path.append(route) }
  func navigateUp() { if !path.isEmpty { path.removeLast() } }
  func popTo(_ route: Route, inclusive: Bool = false) {
    if let idx = path.lastIndex(of: route) {
      let end = inclusive ? idx : idx + 1
      path.removeSubrange(end..<path.count)
    }
  }
  func popToRoot() { path.removeAll() }

  /// Handle a deep link of the form com.google.ai.edge.gallery://<taskId> or
  /// com.google.ai.edge.gallery://model/<taskId>/<modelName>?query=... .
  func handleDeepLink(_ url: URL, modelManager: ModelManagerViewModel) {
    let str = url.absoluteString
    if str.hasPrefix("com.google.ai.edge.gallery://model/") {
      let segments = url.pathComponents.filter { $0 != "/" }
      if segments.count >= 2 {
        let taskId = segments[segments.count - 2]
        let modelName = segments[segments.count - 1]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first(where: { $0.name == "query" })?.value
        if modelManager.getModelByName(modelName) != nil {
          navigate(.model(taskId: taskId, modelName: modelName, query: query))
        }
      }
    } else if str == "com.google.ai.edge.gallery://global_model_manager" {
      navigate(.modelManager)
    } else if let host = url.host {
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "query" })?.value
      if let task = modelManager.getTaskById(host) {
        let defaultModel = task.models.first { modelManager.isModelDownloaded($0) } ?? task.models.first
        if let m = defaultModel {
          navigate(.model(taskId: task.id, modelName: m.name, query: query))
        }
      }
    }
  }
}
