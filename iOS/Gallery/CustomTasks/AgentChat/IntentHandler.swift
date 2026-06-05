// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/IntentHandler.kt

import Foundation
import EventKit
import UIKit

// MARK: - Intent action enum

enum IntentAction: String, CaseIterable {
    case sendEmail = "send_email"
    case sendSms = "send_sms"
    case createCalendarEvent = "create_calendar_event"
    case readCalendarEvents = "read_calendar_events"
    case getCurrentDateAndTime = "get_current_date_and_time"
    case scheduleNotification = "schedule_notification"

    static func from(_ action: String) -> IntentAction? {
        allCases.first { $0.rawValue == action }
    }
}

// MARK: - Parameter structs

private struct SendEmailParams: Codable { let extra_email: String; let extra_subject: String; let extra_text: String }
private struct SendSmsParams: Codable { let phone_number: String; let sms_body: String }
private struct CreateCalendarEventParams: Codable { let title: String; let description: String; let begin_time: String; let end_time: String }
private struct ReadCalendarEventsParams: Codable { let date: String }
struct ScheduleNotificationParams: Codable {
    let title: String; let message: String; let hour: Int; let minute: Int
    let deeplink: String?; let task_id: String?; let model_name: String?
    let year: Int?; let month: Int?; let day: Int?; let repeat_daily: Bool?
}

// MARK: - IntentHandler

enum IntentHandler {
    /// Set by AgentChatScreen before the first model run.
    static var notificationManager: NotificationScheduleManager?

    private static let iso8601 = ISO8601DateFormatter()
    private static let isoNoTz: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()
    private static let dateOnlyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func handleAction(action: String, parameters: String, requestPermission: @escaping (String) async -> Bool) async -> String {
        switch IntentAction.from(action) {
        case .sendEmail:
            return handleSendEmail(parameters: parameters)
        case .sendSms:
            return handleSendSms(parameters: parameters)
        case .createCalendarEvent:
            return await handleCreateCalendarEvent(parameters: parameters, requestPermission: requestPermission)
        case .readCalendarEvents:
            return await handleReadCalendarEvents(parameters: parameters, requestPermission: requestPermission)
        case .getCurrentDateAndTime:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss EEEE"
            return f.string(from: Date())
        case .scheduleNotification:
            return handleScheduleNotification(parameters: parameters)
        case .none:
            return "failed"
        }
    }

    // MARK: - Email

    private static func handleSendEmail(parameters: String) -> String {
        guard let data = parameters.data(using: .utf8),
              let params = try? JSONDecoder().decode(SendEmailParams.self, from: data) else { return "failed" }
        let encodedEmail = params.extra_email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedSubject = params.extra_subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = params.extra_text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:\(encodedEmail)?subject=\(encodedSubject)&body=\(encodedBody)"
        guard let url = URL(string: urlString) else { return "failed" }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
        return "succeeded"
    }

    // MARK: - SMS

    private static func handleSendSms(parameters: String) -> String {
        guard let data = parameters.data(using: .utf8),
              let params = try? JSONDecoder().decode(SendSmsParams.self, from: data) else { return "failed" }
        let encoded = params.sms_body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "sms:\(params.phone_number)&body=\(encoded)") else { return "failed" }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
        return "succeeded"
    }

    // MARK: - Calendar create

    private static func handleCreateCalendarEvent(parameters: String, requestPermission: (String) async -> Bool) async -> String {
        guard let data = parameters.data(using: .utf8),
              let params = try? JSONDecoder().decode(CreateCalendarEventParams.self, from: data),
              let begin = isoNoTz.date(from: params.begin_time),
              let end = isoNoTz.date(from: params.end_time) else { return "failed" }

        // NOTE: On iOS, creating calendar events can be done via EKEventStore or by opening
        // the Calendar app via a URL scheme. We use the EventKit API (requires NSCalendarsUsageDescription).
        // Permission string mirrors Android's READ_CALENDAR / WRITE_CALENDAR.
        let store = EKEventStore()
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToEvents { ok, _ in cont.resume(returning: ok) }
        }
        guard granted else { return "failed: calendar permission denied" }
        let event = EKEvent(eventStore: store)
        event.title = params.title
        event.notes = params.description
        event.startDate = begin
        event.endDate = end
        event.calendar = store.defaultCalendarForNewEvents
        do { try store.save(event, span: .thisEvent); return "succeeded" }
        catch { return "failed: \(error.localizedDescription)" }
    }

    // MARK: - Calendar read

    private static func handleReadCalendarEvents(parameters: String, requestPermission: (String) async -> Bool) async -> String {
        guard let data = parameters.data(using: .utf8),
              let params = try? JSONDecoder().decode(ReadCalendarEventsParams.self, from: data),
              let dateObj = dateOnlyFmt.date(from: params.date) else { return "failed" }

        let store = EKEventStore()
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToEvents { ok, _ in cont.resume(returning: ok) }
        }
        guard granted else { return "failed: READ_CALENDAR permission denied by user" }

        var cal = Calendar.current
        let startOfDay = cal.startOfDay(for: dateObj)
        var comps = DateComponents(); comps.day = 1; comps.second = -1
        let endOfDay = cal.date(byAdding: comps, to: startOfDay)!
        let pred = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: pred)
        struct Dto: Codable { let title: String; let description: String; let begin_time: String; let end_time: String }
        struct Response: Codable { let events: [Dto] }
        let timeFmt = isoNoTz
        let dtos = events.map { e in
            Dto(title: e.title ?? "", description: e.notes ?? "",
                begin_time: timeFmt.string(from: e.startDate), end_time: timeFmt.string(from: e.endDate))
        }
        guard let encoded = try? JSONEncoder().encode(Response(events: dtos)) else { return "failed" }
        return String(data: encoded, encoding: .utf8) ?? "failed"
    }

    // MARK: - Schedule notification

    private static func handleScheduleNotification(parameters: String) -> String {
        guard let data = parameters.data(using: .utf8),
              let params = try? JSONDecoder().decode(ScheduleNotificationParams.self, from: data) else { return "failed" }

        // Build deeplink: mirrors Android logic
        var deeplink = params.deeplink ?? ""
        if deeplink.isEmpty {
            if let taskId = params.task_id, let modelName = params.model_name {
                deeplink = "gallery://model/\(taskId)/\(modelName)?query=\(params.message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            } else if let taskId = params.task_id {
                deeplink = "gallery://\(taskId)/?query=\(params.message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            } else {
                deeplink = "gallery://llm_agent_chat/?query=\(params.message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
        }

        let notification = ScheduledNotification(
            id: UUID().uuidString, title: params.title, message: params.message,
            hour: params.hour, minute: params.minute,
            channelId: "agent_skill_tasks_channel", channelName: "Agent Skill Task",
            deeplink: deeplink, year: params.year ?? 0, month: params.month ?? 0,
            day: params.day ?? 0, repeatDaily: params.repeat_daily ?? false)

        // NOTE: NotificationScheduleManager is injected from AppContainer.
        // IntentHandler cannot access it directly without DI; we store a reference
        // injected by AgentTools/AgentChatScreen. For now we stub with success=false
        // if the manager is not set. Set IntentHandler.notificationManager before use.
        guard let manager = IntentHandler.notificationManager else {
            return "failed: NotificationScheduleManager not configured"
        }
        let success = manager.scheduleNotification(notification)
        return success ? "succeeded" : "failed"
    }
}
