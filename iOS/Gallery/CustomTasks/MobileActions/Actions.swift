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

// Port of customtasks/mobileactions/Actions.kt

import Foundation

// Supported action types.
enum ActionType {
    case flashlightOn
    case flashlightOff
    case createContact
    case sendEmail
    case showLocationOnMap
    case openWifiSettings
    case createCalendarEvent
}

struct FunctionCallDetails {
    let functionName: String
    let parameters: [(String, String)]
    let ts: TimeInterval

    init(functionName: String, parameters: [(String, String)], ts: TimeInterval = Date().timeIntervalSince1970) {
        self.functionName = functionName
        self.parameters = parameters
        self.ts = ts
    }
}

// Base action class.
class Action {
    let type: ActionType
    /// SF Symbol name for the action icon (maps from Android MaterialIcons).
    let iconSystemName: String
    let functionCallDetails: FunctionCallDetails

    init(type: ActionType, iconSystemName: String, functionCallDetails: FunctionCallDetails) {
        self.type = type
        self.iconSystemName = iconSystemName
        self.functionCallDetails = functionCallDetails
    }
}

// Action to turn on flashlight.
final class FlashlightOnAction: Action {
    init() {
        super.init(
            type: .flashlightOn,
            iconSystemName: "flashlight.on.fill",
            functionCallDetails: FunctionCallDetails(functionName: "turnOnFlashlight", parameters: [])
        )
    }
}

// Action to turn off flashlight.
final class FlashlightOffAction: Action {
    init() {
        super.init(
            type: .flashlightOff,
            iconSystemName: "flashlight.off.fill",
            functionCallDetails: FunctionCallDetails(functionName: "turnOffFlashlight", parameters: [])
        )
    }
}

// Action to create contact.
final class CreateContactAction: Action {
    let firstName: String
    let lastName: String
    let phoneNumber: String
    let email: String

    init(firstName: String, lastName: String, phoneNumber: String, email: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.email = email
        super.init(
            type: .createContact,
            iconSystemName: "person.badge.plus",
            functionCallDetails: FunctionCallDetails(
                functionName: "createContact",
                parameters: [
                    ("firstName", firstName),
                    ("lastName", lastName),
                    ("phoneNumber", phoneNumber),
                    ("email", email),
                ]
            )
        )
    }
}

// Action to send email.
final class SendEmailAction: Action {
    let to: String
    let subject: String
    let body: String

    init(to: String, subject: String, body: String) {
        self.to = to
        self.subject = subject
        self.body = body
        super.init(
            type: .sendEmail,
            iconSystemName: "envelope",
            functionCallDetails: FunctionCallDetails(
                functionName: "sendEmail",
                parameters: [("to", to), ("subject", subject), ("body", body)]
            )
        )
    }
}

// Action to show a location on map.
final class ShowLocationOnMapAction: Action {
    let location: String

    init(location: String) {
        self.location = location
        super.init(
            type: .showLocationOnMap,
            iconSystemName: "map",
            functionCallDetails: FunctionCallDetails(
                functionName: "showLocationOnMap",
                parameters: [("location", location)]
            )
        )
    }
}

// Action to open wifi settings.
final class OpenWifiSettingsAction: Action {
    init() {
        super.init(
            type: .openWifiSettings,
            iconSystemName: "wifi",
            // NOTE: iOS does not have a direct "open Wi-Fi settings" deeplink.
            // We open the Settings app root via UIApplication.shared.open(URL("App-Prefs:Wifi")...)
            // which works on some iOS versions but is not public API. See MobileActionsViewModel.
            functionCallDetails: FunctionCallDetails(functionName: "openWifiSettings", parameters: [])
        )
    }
}

// Action to create calendar event.
final class CreateCalendarEventAction: Action {
    let datetime: String
    let title: String

    init(datetime: String, title: String) {
        self.datetime = datetime
        self.title = title
        super.init(
            type: .createCalendarEvent,
            iconSystemName: "calendar.badge.plus",
            functionCallDetails: FunctionCallDetails(
                functionName: "createCalendarEvent",
                parameters: [("datetime", datetime), ("title", title)]
            )
        )
    }
}
