// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/kakao/KakaoShareTools.kt
//
// NOTE: On Android, KakaoTalk accepts a standard ACTION_SEND intent with the KakaoTalk package
// name, opening its chat picker. On iOS, there is no equivalent intent system — KakaoTalk for iOS
// does not register a public URL scheme that accepts pre-composed messages. The closest iOS
// equivalent is using UIActivityViewController with the system share sheet, which may or may not
// route to KakaoTalk depending on what the user has installed.
//
// This file implements the best-effort iOS equivalent: a UIActivityViewController share sheet
// with the composed message. The tool signals "shared" once the user confirms in the share sheet.
// It cannot guarantee delivery to a specific KakaoTalk contact (the same limitation applies on
// Android where the user picks the recipient inside KakaoTalk).

import Foundation
import UIKit

// MARK: - KakaoShareTools

final class KakaoShareTools {
    private let onShared: (String) -> Void

    init(onShared: @escaping (String) -> Void = { _ in }) {
        self.onShared = onShared
    }

    /// Sends a message via the iOS share sheet (which may include KakaoTalk if installed).
    /// Mirrors `@Tool fun sendKakaoMessage(recipient, message)`.
    func sendKakaoMessage(recipient: String, message: String) async -> [String: String] {
        if message.trimmingCharacters(in: .whitespaces).isEmpty {
            return ["status": "failed", "error": "Message body is empty"]
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                // NOTE: UIActivityViewController requires a UIViewController to present from.
                // In a SwiftUI app, obtain the root view controller from the active scene.
                guard let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.windows.first?.rootViewController })
                    .first else {
                    continuation.resume(returning: [
                        "status": "failed",
                        "error": "Unable to present share sheet — no root view controller"
                    ])
                    return
                }

                let activityVC = UIActivityViewController(activityItems: [message], applicationActivities: nil)
                activityVC.completionWithItemsHandler = { activityType, completed, _, error in
                    if let err = error {
                        continuation.resume(returning: ["status": "failed", "error": err.localizedDescription])
                    } else if completed {
                        self.onShared(recipient)
                        continuation.resume(returning: [
                            "status": "shared",
                            "recipient": recipient,
                            "note": "Share sheet presented; ask the user to pick the recipient and confirm sending."
                        ])
                    } else {
                        continuation.resume(returning: ["status": "cancelled", "note": "User cancelled the share sheet."])
                    }
                }
                rootVC.present(activityVC, animated: true)
            }
        }
    }
}
