// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/home/SettingsDialog.kt

import SwiftUI

private let THEME_OPTIONS: [Theme] = [.themeAuto, .themeLight, .themeDark]

/// Settings dialog: theme switcher, HuggingFace token management, licenses, TOS.
/// Mirrors `SettingsDialog`.
struct SettingsDialog: View {
  let curThemeOverride: Theme
  let modelManagerViewModel: ModelManagerViewModel
  let onDismissed: () -> Void

  @State private var selectedTheme: Theme
  @State private var customHfToken: String = ""
  @State private var hfTokenData: AccessTokenData?
  @State private var showTos = false

  @Environment(\.galleryColors) private var colors

  private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  private let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

  init(curThemeOverride: Theme, modelManagerViewModel: ModelManagerViewModel, onDismissed: @escaping () -> Void) {
    self.curThemeOverride = curThemeOverride
    self.modelManagerViewModel = modelManagerViewModel
    self.onDismissed = onDismissed
    _selectedTheme = State(initialValue: curThemeOverride)
    _hfTokenData = State(initialValue: modelManagerViewModel.getTokenStatusAndData().data)
  }

  var body: some View {
    ZStack {
      // Tappable background to dismiss keyboard
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }

      VStack(alignment: .leading, spacing: 16) {
        // Title
        VStack(alignment: .leading, spacing: 4) {
          Text("Settings")
            .font(AppTypography.titleLarge)
            .foregroundStyle(colors.onSurface)

          Text("App version: \(appVersion) (\(appBuild))")
            .font(AppTypography.labelSmallNarrow)
            .foregroundStyle(colors.onSurfaceVariant)
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            // Theme picker
            VStack(alignment: .leading, spacing: 8) {
              Text("Theme")
                .font(AppFont.font(size: 14, weight: .medium))
                .foregroundStyle(colors.onSurface)

              Picker("", selection: $selectedTheme) {
                ForEach(THEME_OPTIONS, id: \.self) { theme in
                  Text(themeLabel(theme)).tag(theme)
                }
              }
              .pickerStyle(.segmented)
              .onChange(of: selectedTheme) { _, newValue in
                modelManagerViewModel.saveThemeOverride(newValue)
              }
            }

            Divider()

            // HuggingFace token
            VStack(alignment: .leading, spacing: 4) {
              Text("HuggingFace access token")
                .font(AppFont.font(size: 14, weight: .medium))
                .foregroundStyle(colors.onSurface)

              if let token = hfTokenData, !token.accessToken.isEmpty {
                let preview = String(token.accessToken.prefix(16)) + "..."
                Text(preview)
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(colors.onSurfaceVariant)

                let expDate = Date(timeIntervalSince1970: Double(token.expiresAtMs) / 1000)
                let formatter: DateFormatter = {
                  let f = DateFormatter()
                  f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                  return f
                }()
                Text("Expires at: \(formatter.string(from: expDate))")
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(colors.onSurfaceVariant)
              } else {
                Text("Not available")
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(colors.onSurfaceVariant)

                Text("The token will be automatically retrieved when a gated model is downloaded")
                  .font(AppTypography.bodySmall)
                  .foregroundStyle(colors.onSurfaceVariant)
              }

              HStack(spacing: 8) {
                Button("Clear") {
                  modelManagerViewModel.clearAccessToken()
                  hfTokenData = nil
                }
                .buttonStyle(.bordered)
                .disabled(hfTokenData == nil)

                HStack {
                  TextField("Enter token manually", text: $customHfToken)
                    .font(AppTypography.bodySmall)
                    .padding(.leading, 12)
                    .onSubmit { saveToken() }

                  if !customHfToken.isEmpty {
                    Button(action: saveToken) {
                      Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.primary)
                    }
                    .padding(.trailing, 8)
                  }
                }
                .frame(height: 40)
                .overlay(
                  RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(colors.outline, lineWidth: 1)
                )
              }
            }

            Divider()

            // Third-party licenses
            // NOTE: iOS does not have OssLicensesMenuActivity. We open a local licenses URL or skip.
            VStack(alignment: .leading, spacing: 8) {
              Text("Third-party libraries")
                .font(AppFont.font(size: 14, weight: .medium))
                .foregroundStyle(colors.onSurface)

              Button("View licenses") {
                // NOTE: Open bundled licenses HTML if available.
                if let url = Bundle.main.url(forResource: "licenses", withExtension: "html") {
                  UIApplication.shared.open(url)
                }
              }
              .buttonStyle(.bordered)
            }

            Divider()

            // ToS
            VStack(alignment: .leading, spacing: 8) {
              Text(Str.settingsDialogTosTitle)
                .font(AppFont.font(size: 14, weight: .medium))
                .foregroundStyle(colors.onSurface)

              Button(Str.settingsDialogViewAppTermsOfService) {
                showTos = true
              }
              .buttonStyle(.bordered)

              ClickableLink(
                url: "https://ai.google.dev/gemma/terms",
                linkText: Str.tosDialogTitleGemma
              )

              ClickableLink(
                url: "https://ai.google.dev/gemma/prohibited_use_policy",
                linkText: Str.settingsDialogGemmaProhibitedUsePolicy
              )
              .padding(.top, 8)
            }
          }
          .padding(.bottom, 8)
        }

        // Close button
        HStack {
          Spacer()
          Button("Close") { onDismissed() }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
      }
      .padding(20)
      .background(colors.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(radius: 8)
      .padding(24)
    }
    .sheet(isPresented: $showTos) {
      // NOTE: AppTosDialog is owned by the common/tos agent — reference by name.
      // AppTosDialog(onTosAccepted: { showTos = false }, viewingMode: true)
      Text("Terms of Service")
        .padding()
    }
  }

  private func saveToken() {
    let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + 1000 * 60 * 60 * 24 * 365 * 10
    modelManagerViewModel.saveAccessToken(
      accessToken: customHfToken,
      refreshToken: "",
      expiresAt: expiresAt
    )
    hfTokenData = modelManagerViewModel.getTokenStatusAndData().data
    customHfToken = ""
    hideKeyboard()
  }
}

private func themeLabel(_ theme: Theme) -> String {
  switch theme {
  case .themeAuto: return "Auto"
  case .themeLight: return "Light"
  case .themeDark: return "Dark"
  default: return "Unknown"
  }
}

private func hideKeyboard() {
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
