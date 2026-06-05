/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/DownloadRepository.kt
//
// Android used WorkManager (a foreground service) to download model files. iOS
// mirrors the same repository surface with URLSession download tasks, reporting
// progress through the same `ModelDownloadStatus` callback used by the Android app.

import Foundation

struct AGWorkInfo {
  let taskId: String
  let modelName: String
  let workId: String
}

/// Mirrors `interface DownloadRepository`.
protocol DownloadRepository: AnyObject {
  func downloadModel(task: Task, model: Model, onStatusUpdated: @escaping (Model, ModelDownloadStatus) -> Void)
  func cancelDownloadModel(model: Model)
  func cancelAll(onComplete: @escaping () -> Void)
  func observerWorkerProgress(onStatusUpdated: @escaping (Model, ModelDownloadStatus) -> Void)
}

/// URLSession-backed implementation. Mirrors `DefaultDownloadRepository`.
final class DefaultDownloadRepository: NSObject, DownloadRepository {
  private var tasks: [String: URLSessionDownloadTask] = [:]
  private var statusHandlers: [String: (Model, ModelDownloadStatus) -> Void] = [:]
  private var models: [String: Model] = [:]
  private lazy var session: URLSession = {
    let cfg = URLSessionConfiguration.default
    return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
  }()

  func downloadModel(task: Task, model: Model, onStatusUpdated: @escaping (Model, ModelDownloadStatus) -> Void) {
    guard let url = URL(string: model.url) else {
      onStatusUpdated(model, ModelDownloadStatus(status: .failed, errorMessage: "Invalid URL"))
      return
    }
    statusHandlers[model.name] = onStatusUpdated
    models[model.name] = model
    var request = URLRequest(url: url)
    if let token = model.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let downloadTask = session.downloadTask(with: request)
    downloadTask.taskDescription = model.name
    tasks[model.name] = downloadTask
    onStatusUpdated(model, ModelDownloadStatus(status: .inProgress, totalBytes: model.totalBytes))
    downloadTask.resume()
  }

  func cancelDownloadModel(model: Model) {
    tasks[model.name]?.cancel()
    tasks.removeValue(forKey: model.name)
  }

  func cancelAll(onComplete: @escaping () -> Void) {
    tasks.values.forEach { $0.cancel() }
    tasks.removeAll()
    onComplete()
  }

  func observerWorkerProgress(onStatusUpdated: @escaping (Model, ModelDownloadStatus) -> Void) {
    // No persistent worker on iOS; in-flight tasks already report via their handler.
  }
}

extension DefaultDownloadRepository: URLSessionDownloadDelegate {
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard let name = downloadTask.taskDescription, let model = models[name] else { return }
    let status = ModelDownloadStatus(
      status: .inProgress,
      totalBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : model.totalBytes,
      receivedBytes: totalBytesWritten)
    DispatchQueue.main.async { self.statusHandlers[name]?(model, status) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard let name = downloadTask.taskDescription, let model = models[name] else { return }
    let dest = URL(fileURLWithPath: model.getPath())
    FileSystem.ensureDir(dest.deletingLastPathComponent())
    try? FileManager.default.removeItem(at: dest)
    try? FileManager.default.moveItem(at: location, to: dest)
    DispatchQueue.main.async {
      self.statusHandlers[name]?(model, ModelDownloadStatus(status: .succeeded, totalBytes: model.totalBytes,
                                                            receivedBytes: model.totalBytes))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let name = task.taskDescription, let model = models[name], let error else { return }
    DispatchQueue.main.async {
      self.statusHandlers[name]?(model, ModelDownloadStatus(status: .failed, errorMessage: error.localizedDescription))
    }
  }
}
