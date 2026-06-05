/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of proto/scheduled_notification.proto -> Codable Swift structs.

import Foundation

struct ScheduledNotification: Codable, Identifiable {
  var id: String = ""
  var title: String = ""
  var message: String = ""
  var channelId: String = ""
  var channelName: String = ""
  var hour: Int32 = 0
  var minute: Int32 = 0
  var year: Int32? = nil
  var month: Int32? = nil
  var day: Int32? = nil
  var repeatDaily: Bool? = nil
  var deeplink: String? = nil
}

struct ScheduledNotifications: Codable {
  var notification: [ScheduledNotification] = []
  static let defaultInstance = ScheduledNotifications()
}
