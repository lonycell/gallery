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

// Port of customtasks/mobileactions/MobileActionsTools.kt
//
// NOTE: Android used `@Tool`/`@ToolParam`/`ToolSet` annotations from the
// com.google.ai.edge.litertlm library for automatic reflection-based tool
// registration. iOS has no equivalent library; tools are represented as
// JSON function-spec dictionaries (OpenAI-style) passed to LlmModelHelper.
// The `MobileActionsToolSet` class provides the same dispatch logic and
// callback mechanism; the JSON specs are consumed by MobileActionsTask when
// building the tools: [ToolProvider] list that is handed to
// LlmModelHelper.initialize(). Route through LlmModelHelper — do NOT call
// on-device inference directly.

import Foundation

/// Mirrors the `@ToolSet` class `MobileActionsTools`.
/// `onFunctionCalled` fires for every recognized tool invocation.
final class MobileActionsToolSet {
    let onFunctionCalled: (Action) -> Void

    init(onFunctionCalled: @escaping (Action) -> Void) {
        self.onFunctionCalled = onFunctionCalled
    }

    // MARK: - Tool functions (mirrors @Tool-annotated methods)

    /// Turns the flashlight on.
    /// Returns a result dict sent back to the model.
    func turnOnFlashlight() -> [String: String] {
        onFunctionCalled(FlashlightOnAction())
        return ["result": "success"]
    }

    /// Turns the flashlight off.
    func turnOffFlashlight() -> [String: String] {
        onFunctionCalled(FlashlightOffAction())
        return ["result": "success"]
    }

    /// Creates a contact in the phone's contact list.
    func createContact(firstName: String, lastName: String, phoneNumber: String, email: String) -> [String: String] {
        onFunctionCalled(CreateContactAction(firstName: firstName, lastName: lastName,
                                             phoneNumber: phoneNumber, email: email))
        return [
            "result": "success",
            "first_name": firstName,
            "last_name": lastName,
            "phone_number": phoneNumber,
            "email": email,
        ]
    }

    /// Sends an email.
    func sendEmail(to: String, subject: String, body: String) -> [String: String] {
        onFunctionCalled(SendEmailAction(to: to, subject: subject, body: body))
        return ["result": "success", "to": to, "subject": subject, "body": body]
    }

    /// Shows a location on the map.
    func showLocationOnMap(location: String) -> [String: String] {
        onFunctionCalled(ShowLocationOnMapAction(location: location))
        return ["result": "success", "location": location]
    }

    /// Opens the WiFi settings.
    func openWifiSettings() -> [String: String] {
        onFunctionCalled(OpenWifiSettingsAction())
        return ["result": "success"]
    }

    /// Creates a new calendar event.
    func createCalendarEvent(datetime: String, title: String) -> [String: String] {
        onFunctionCalled(CreateCalendarEventAction(datetime: datetime, title: title))
        return ["result": "success", "datetime": datetime, "title": title]
    }

    // MARK: - JSON function specs
    //
    // NOTE: These mirror the @Tool + @ToolParam annotations on Android. The
    // LlmModelHelper stub ignores them; a real MediaPipe/LiteRT bridge would
    // parse them to build the function-calling context.

    static var functionSpecs: [[String: Any]] {
        [
            [
                "name": "turnOnFlashlight",
                "description": "Turns the flashlight on",
                "parameters": ["type": "object", "properties": [:], "required": []],
            ],
            [
                "name": "turnOffFlashlight",
                "description": "Turns the flashlight off",
                "parameters": ["type": "object", "properties": [:], "required": []],
            ],
            [
                "name": "createContact",
                "description": "Creates a contact in the phone's contact list.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "firstName":   ["type": "string", "description": "The first name of the contact."],
                        "lastName":    ["type": "string", "description": "The last name of the contact."],
                        "phoneNumber": ["type": "string", "description": "The phone number of the contact."],
                        "email":       ["type": "string", "description": "The email address of the contact."],
                    ],
                    "required": ["firstName", "lastName", "phoneNumber", "email"],
                ],
            ],
            [
                "name": "sendEmail",
                "description": "Sends an email.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "to":      ["type": "string", "description": "The email address of the recipient."],
                        "subject": ["type": "string", "description": "The subject of the email."],
                        "body":    ["type": "string", "description": "The body of the email."],
                    ],
                    "required": ["to", "subject", "body"],
                ],
            ],
            [
                "name": "showLocationOnMap",
                "description": "Shows a location on the map.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "location": ["type": "string",
                                     "description": "The location to search for. May be the name of a place, a business, or an address."],
                    ],
                    "required": ["location"],
                ],
            ],
            [
                "name": "openWifiSettings",
                "description": "Opens the WiFi settings.",
                "parameters": ["type": "object", "properties": [:], "required": []],
            ],
            [
                "name": "createCalendarEvent",
                "description": "Creates a new calendar event.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "datetime": ["type": "string",
                                     "description": "The date and time of the event in the format YYYY-MM-DDTHH:MM:SS."],
                        "title": ["type": "string", "description": "The title of the event."],
                    ],
                    "required": ["datetime", "title"],
                ],
            ],
        ]
    }

    // MARK: - Dispatch

    /// Dispatches a raw function-call JSON payload (from the model) to the
    /// matching tool function and returns the result as a JSON string.
    func dispatch(functionName: String, args: [String: Any]) -> String {
        var result: [String: Any]
        switch functionName {
        case "turnOnFlashlight":
            result = turnOnFlashlight()
        case "turnOffFlashlight":
            result = turnOffFlashlight()
        case "createContact":
            result = createContact(
                firstName:   args["firstName"] as? String ?? "",
                lastName:    args["lastName"] as? String ?? "",
                phoneNumber: args["phoneNumber"] as? String ?? "",
                email:       args["email"] as? String ?? ""
            )
        case "sendEmail":
            result = sendEmail(
                to:      args["to"] as? String ?? "",
                subject: args["subject"] as? String ?? "",
                body:    args["body"] as? String ?? ""
            )
        case "showLocationOnMap":
            result = showLocationOnMap(location: args["location"] as? String ?? "")
        case "openWifiSettings":
            result = openWifiSettings()
        case "createCalendarEvent":
            result = createCalendarEvent(
                datetime: args["datetime"] as? String ?? "",
                title:    args["title"] as? String ?? ""
            )
        default:
            result = ["result": "unknown_function"]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
