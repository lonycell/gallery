// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of notifications/NotificationPendingIntentHelper.kt +
//         notifications/NotificationReceiver.kt +
//         notifications/BootReceiver.kt
//
// Android mapping:
//
//   NotificationPendingIntentHelper  — The extra keys and PendingIntent builder.
//     On iOS, UNNotificationRequest carries the same data through
//     `UNMutableNotificationContent.userInfo`. This file declares the matching
//     userInfo key constants and helper methods.
//
//   NotificationReceiver (BroadcastReceiver) — Fired when the AlarmManager alarm
//     fires; posts the actual system notification and removes one-shot schedules.
//     On iOS, UNUserNotificationCenter handles delivery automatically from the
//     UNNotificationRequest registered by NotificationScheduleManager. The iOS
//     equivalent of the "post + cleanup" logic lives in this delegate.
//
//   BootReceiver (BroadcastReceiver, ACTION_BOOT_COMPLETED) — Reschedules all
//     notifications after reboot. On iOS, UNCalendarNotificationTrigger requests
//     survive a reboot inside the system notification store, so no explicit
//     boot-time rescheduling is needed.
//
//     NOTE: There is no UIApplicationDelegate callback that is an exact match for
//     ACTION_BOOT_COMPLETED. The closest hook is `applicationDidBecomeActive`, but
//     since iOS restores pending UNNotificationRequests across reboots automatically
//     (unlike Android AlarmManager), the BootReceiver logic is a no-op here. If
//     the app ever switches to custom background delivery (BGAppRefreshTask), call
//     `NotificationScheduleManager.rescheduleAllNotifications()` from that handler.
//
//   Deep-link routing — Android's NotificationReceiver created an Intent with
//     ACTION_VIEW and a URI. iOS equivalent: attach a "deeplink" string to
//     `userInfo`, then handle it in `userNotificationCenter(_:didReceive:)`.
//     See `handleDeepLink(url:)` on `Router` for the actual routing logic.

import Foundation
import UserNotifications
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Gallery",
                         category: "NotificationActionHandler")

// MARK: - UserInfo key constants
// (mirror the EXTRA_* constants from NotificationPendingIntentHelper.kt)

enum NotificationUserInfoKey {
    static let id          = "id"
    static let title       = "title"
    static let message     = "message"
    static let deeplink    = "deeplink"
    static let repeatDaily = "repeat_daily"
    static let hour        = "hour"
    static let minute      = "minute"
    static let channelId   = "channel_id"
    static let channelName = "channel_name"
}

// MARK: - NotificationActionHandler

/// `UNUserNotificationCenterDelegate` that handles:
///
///  1. Foreground delivery — shows a banner even when the app is open (mirrors the
///     system behaviour on Android where notifications always appear).
///  2. Tap handling — extracts the `deeplink` from `userInfo` and routes via `Router`.
///  3. One-shot cleanup — after delivering a non-repeating notification, removes it
///     from `NotificationScheduleManager` so the Notifications screen stays accurate.
///
/// Instantiated once in `GalleryApp` / `AppContainer` and assigned to
/// `UNUserNotificationCenter.current().delegate`.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {

    private let scheduleManager: NotificationScheduleManager
    /// Called when a deeplink URL needs to be handled. Wire to `Router.handleDeepLink`.
    var deepLinkHandler: ((URL) -> Void)?

    init(scheduleManager: NotificationScheduleManager) {
        self.scheduleManager = scheduleManager
        super.init()
    }

    // MARK: Foreground delivery

    /// Allow banners / sounds when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: Tap handling + one-shot cleanup

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        let id = userInfo[NotificationUserInfoKey.id] as? String ?? response.notification.request.identifier

        // NOTE: Android's NotificationReceiver removed a one-shot notification from
        // the schedule after firing. We mirror that here: if `repeat_daily` is absent
        // or false, remove the entry so the Notifications screen reflects reality.
        let repeatDaily = userInfo[NotificationUserInfoKey.repeatDaily] as? Bool ?? false
        if !repeatDaily && !id.isEmpty {
            log.debug("Removing delivered one-shot notification '\(id)'")
            scheduleManager.removeNotification(id: id)
        }

        // Deep-link routing
        if let deeplinkStr = userInfo[NotificationUserInfoKey.deeplink] as? String,
           !deeplinkStr.isEmpty,
           let url = URL(string: deeplinkStr) {
            log.debug("Handling deeplink: \(deeplinkStr)")
            deepLinkHandler?(url)
        }
    }
}

// MARK: - BootReceiver note

// NOTE: Android's BootReceiver (ACTION_BOOT_COMPLETED → rescheduleAllNotifications)
// has no direct iOS equivalent. On iOS, UNCalendarNotificationTrigger requests are
// stored by the OS and survive reboot automatically. If behavior changes in a future
// OS version, call `NotificationScheduleManager.rescheduleAllNotifications()` from
// the BGAppRefreshTask handler or from `applicationDidBecomeActive` as a guard.
