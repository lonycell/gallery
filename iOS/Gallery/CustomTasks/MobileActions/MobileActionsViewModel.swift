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

// Port of customtasks/mobileactions/MobileActionsViewModel.kt

import Foundation
import UIKit
import Combine
// NOTE: iOS Contacts / Calendar imports replace Android's ContactsContract /
// CalendarContract; these are available in Contacts.framework and EventKit.
import Contacts
import EventKit
import AVFoundation

/// UI state for the MobileActions screen. Mirrors `MobileActionsUiState`.
struct MobileActionsUiState {
    var showWelcomeMessage: Bool = true
    var processing: Bool = false
    var userPrompt: String = ""
    var modelResponse: String = ""
    var functionCallDetails: [String] = []
    var noFunctionRecognized: Bool = false
}

@MainActor
final class MobileActionsViewModel: ObservableObject {
    @Published var uiState = MobileActionsUiState()

    private var isResettingConversation = false

    // MARK: - State mutations

    func reset() {
        turnOffTorch()
        uiState.showWelcomeMessage = true
        uiState.userPrompt = ""
        uiState.modelResponse = ""
        uiState.noFunctionRecognized = false
        uiState.functionCallDetails = []
    }

    func cleanUp() {
        turnOffTorch()
    }

    func setProcessing(_ processing: Bool) { uiState.processing = processing }
    func setShowWelcomeMessage(_ show: Bool) { uiState.showWelcomeMessage = show }
    func setUserPrompt(_ prompt: String) { uiState.userPrompt = prompt }
    func setModelResponse(_ response: String) { uiState.modelResponse = response }
    func appendModelResponse(_ partial: String) { uiState.modelResponse += partial }
    func addFunctionCallDetails(_ details: String) { uiState.functionCallDetails.append(details) }
    func clearFunctionCallDetails() { uiState.functionCallDetails = [] }
    func setNoFunctionRecognized(_ value: Bool) { uiState.noFunctionRecognized = value }

    // MARK: - Inference
    //
    // NOTE: Android drove inference via LlmChatModelHelper (litertlm).
    // On iOS we call through model.runtimeHelper (LlmModelHelper protocol) which
    // is backed by StubLlmModelHelper until a real on-device runtime is wired in.

    func processUserPrompt(
        model: Model,
        userPrompt: String,
        onProcessDone: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard model.instance != nil else {
            setProcessing(false)
            return
        }

        setProcessing(true)
        setShowWelcomeMessage(false)
        setModelResponse("")
        setNoFunctionRecognized(false)
        clearFunctionCallDetails()
        setUserPrompt(userPrompt)

        // NOTE: real function-calling dispatch happens inside the LlmModelHelper
        // implementation (litertlm/MediaPipe). The stub streams a plain text reply.
        // Route through AppContainer.sharedLlmHelper (set at app launch).
        AppContainer.sharedLlmHelper?.runInference(
            model: model,
            input: userPrompt,
            resultListener: { [weak self] partial, done, _ in
                guard let self else { return }
                Task { @MainActor in
                    if !partial.hasPrefix("<ctrl") {
                        self.appendModelResponse(partial)
                    }
                    if done {
                        self.setProcessing(false)
                        onProcessDone()
                    }
                }
            },
            cleanUpListener: {},
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.setProcessing(false)
                    onError(error)
                }
            }
        )
    }

    // MARK: - Action execution
    //
    // Maps iOS-equivalent APIs to the Android actions.

    func performAction(_ action: Action) -> String {
        switch action {
        case is FlashlightOnAction:
            return setFlashlight(enabled: true)
        case is FlashlightOffAction:
            return setFlashlight(enabled: false)
        case let a as CreateContactAction:
            return createContact(firstName: a.firstName, lastName: a.lastName,
                                  phoneNumber: a.phoneNumber, email: a.email)
        case let a as SendEmailAction:
            return sendEmail(to: a.to, subject: a.subject, body: a.body)
        case let a as ShowLocationOnMapAction:
            return showLocationOnMap(location: a.location)
        case is OpenWifiSettingsAction:
            return openWifiSettings()
        case let a as CreateCalendarEventAction:
            return createCalendarEvent(datetime: a.datetime, title: a.title)
        default:
            return ""
        }
    }

    // MARK: - Private device APIs

    private func setFlashlight(enabled: Bool) -> String {
        // NOTE: iOS torch control via AVCaptureDevice, replacing Android CameraManager.
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return "이 기기는 플래시라이트를 지원하지 않습니다."
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            return error.localizedDescription
        }
        return ""
    }

    private func turnOffTorch() { _ = setFlashlight(enabled: false) }

    private func createContact(firstName: String, lastName: String, phoneNumber: String, email: String) -> String {
        // NOTE: iOS Contacts framework (CNContactStore) replaces Android ContactsContract intent.
        // On iOS we open the native Contacts app via CNContactViewController, which requires a
        // UIViewController context. Here we use a URL-based deep link as the simplest approach;
        // a full UI integration would present CNContactViewController from the root ViewController.
        let name = "\(firstName) \(lastName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phone = phoneNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // NOTE: there is no public URL scheme to pre-fill Contacts on iOS.
        // The best alternative is to open the Contacts app and let the user fill details,
        // or to save silently via CNContactStore (requires NSContactsUsageDescription).
        // We use the silent CNContactStore save here; add NSContactsUsageDescription to Info.plist.
        let store = CNContactStore()
        let contact = CNMutableContact()
        contact.givenName = firstName
        contact.familyName = lastName
        let phoneValue = CNLabeledValue(label: CNLabelWork,
                                        value: CNPhoneNumber(stringValue: phoneNumber))
        contact.phoneNumbers = [phoneValue]
        let emailValue = CNLabeledValue<NSString>(label: CNLabelWork, value: email as NSString)
        contact.emailAddresses = [emailValue]
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(request)
        } catch {
            return error.localizedDescription
        }
        return ""
    }

    private func sendEmail(to: String, subject: String, body: String) -> String {
        // NOTE: Opens the system mail composer via mailto: URL, mirroring Android's ACTION_SEND.
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:\(to)?subject=\(encodedSubject)&body=\(encodedBody)"
        guard let url = URL(string: urlString) else { return "잘못된 이메일 주소입니다." }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
        return ""
    }

    private func showLocationOnMap(location: String) -> String {
        // NOTE: Opens Apple Maps via maps: URL, replacing Android's geo: intent.
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "maps://?q=\(encoded)") else { return "잘못된 위치입니다." }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
        return ""
    }

    private func openWifiSettings() -> String {
        // NOTE: iOS does not expose a public "open Wi-Fi settings" URL.
        // App-Prefs:root=WIFI works on some versions but is a private API.
        // The App Store-safe option is to open Settings.app root.
        // We attempt App-Prefs first and fall back to the Settings root.
        if let url = URL(string: "App-Prefs:root=WIFI") {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        return ""
    }

    private func createCalendarEvent(datetime: String, title: String) -> String {
        // NOTE: iOS EventKit replaces Android's CalendarContract intent.
        // Requires NSCalendarsUsageDescription in Info.plist.
        let store = EKEventStore()
        // Parse datetime (YYYY-MM-DDTHH:MM:SS).
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let startDate = formatter.date(from: datetime) ?? Date()
        let endDate = startDate.addingTimeInterval(3600)

        store.requestAccess(to: .event) { granted, error in
            guard granted, error == nil else { return }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
            } catch {
                // Silently ignore; a production app would surface this to the user.
            }
        }
        return ""
    }
}

// NOTE: MobileActionsViewModel uses AppContainer.sharedLlmHelper (set at app launch)
// for inference, matching the Android pattern where LlmChatModelHelper was a singleton
// injected via Hilt. The ViewModel's processUserPrompt calls through that shared helper.
