/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of common/ProjectConfig.kt — Hugging Face OAuth endpoints (AppAuth on
// Android; AuthenticationServices/ASWebAuthenticationSession on iOS).

import Foundation

enum ProjectConfig {
  static let clientId = "REPLACE_WITH_YOUR_CLIENT_ID_IN_HUGGINGFACE_APP"
  static let redirectUri = "REPLACE_WITH_YOUR_REDIRECT_URI_IN_HUGGINGFACE_APP"
  static let authEndpoint = URL(string: "https://huggingface.co/oauth/authorize")!
  static let tokenEndpoint = URL(string: "https://huggingface.co/oauth/token")!
}
