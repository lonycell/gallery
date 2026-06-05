/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of notifications/NotificationScheduleManager.kt
//
// Android used AlarmManager + a JSON file of ScheduledNotifications. iOS uses
// UNUserNotificationCenter with calendar triggers, keeping the same public API.

import Foundation
import UserNotifications

final class NotificationScheduleManager {
  private let store: DataStoreRepository
  private let fileURL = FileSystem.appFilesDir.appendingPathComponent("scheduled_notifications.json")
  private(set) var notifications: [ScheduledNotification] = []

  init(store: DataStoreRepository) { self.store = store }

  func initialize() { loadNotifications() }

  private func loadNotifications() {
    guard let data = try? Data(contentsOf: fileURL),
          let parsed = try? JSONDecoder().decode(ScheduledNotifications.self, from: data) else {
      notifications = []
      return
    }
    notifications = parsed.notification
  }

  private func saveNotifications() {
    let wrapper = ScheduledNotifications(notification: notifications)
    if let data = try? JSONEncoder().encode(wrapper) { try? data.write(to: fileURL) }
  }

  @discardableResult
  func scheduleNotification(_ notification: ScheduledNotification) -> Bool {
    notifications.removeAll { $0.id == notification.id }
    notifications.append(notification)
    saveNotifications()
    setAlarm(for: notification)
    return true
  }

  private func setAlarm(for notification: ScheduledNotification) {
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.message
    if let deeplink = notification.deeplink { content.userInfo = ["deeplink": deeplink] }

    var components = DateComponents()
    components.hour = Int(notification.hour)
    components.minute = Int(notification.minute)
    if let y = notification.year { components.year = Int(y) }
    if let mo = notification.month { components.month = Int(mo) }
    if let d = notification.day { components.day = Int(d) }
    let repeats = notification.repeatDaily == true

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
    let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
  }

  func rescheduleAllNotifications() {
    for n in notifications { setAlarm(for: n) }
  }

  func removeNotification(id: String) {
    notifications.removeAll { $0.id == id }
    saveNotifications()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
  }
}
