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

// Port of customtasks/tinygarden/TinyGardenScreen.kt
//
// The Android screen embedded a WebView loaded from assets via WebViewAssetLoader.
// On iOS we use WKWebView loaded from the app bundle
// (Gallery/Resources/tinygarden/index.html). A JS bridge method
// `tinyGarden.runCommands(json)` is called from Swift exactly like the Android
// `evaluateJavascript("tinyGarden.runCommands('$commandJson')")`.

import SwiftUI
import WebKit
import CryptoKit

// MARK: - WKWebView SwiftUI wrapper

/// SwiftUI wrapper for the TinyGarden WKWebView.
struct TinyGardenWebView: UIViewRepresentable {
    let onPageLoaded: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageLoaded: onPageLoaded) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow audio without a user gesture, mirroring `mediaPlaybackRequiresUserGesture = false`.
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false

        // Load the bundled HTML file.
        // NOTE: On Android WebViewAssetLoader served assets from `assets/tinygarden/index.html`.
        // On iOS we locate the file in the main bundle.
        if let url = Bundle.main.url(forResource: "index", withExtension: "html",
                                      subdirectory: "tinygarden") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onPageLoaded: (WKWebView) -> Void
        init(onPageLoaded: @escaping (WKWebView) -> Void) { self.onPageLoaded = onPageLoaded }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageLoaded(webView)
        }
    }
}

// MARK: - Main screen

/// Main screen for the Tiny Garden game.
/// Mirrors `TinyGardenScreen` + `MainUi` composables.
struct TinyGardenScreen: View {
    let task: Task
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    let tools: [ToolProvider]
    var bottomPadding: CGFloat = 0
    var setAppBarControlsDisabled: (Bool) -> Void = { _ in }
    var setTopBarVisible: (Bool) -> Void = { _ in }

    /// Async stream of commands produced by TinyGardenToolSet.
    /// Mirrors `commandFlow: Flow<TinyGardenCommand>` on Android.
    let commandFlow: AsyncStream<TinyGardenCommand>

    @ObservedObject var viewModel: TinyGardenViewModel

    @Environment(\.galleryColors) private var colors
    @Environment(\.customColors) private var customColors

    @State private var webView: WKWebView? = nil
    @State private var inputText: String = ""
    @State private var showConversationHistoryPanel: Bool = false
    @State private var showErrorDialog: Bool = false
    @State private var errorDialogContent: String = ""
    @State private var prevSeed: String = ""
    @State private var prevPlots: String = ""
    @State private var prevAction: String = ""

    var body: some View {
        let modelManagerState = modelManagerViewModel.uiState
        let model = modelManagerState.selectedModel

        ZStack {
            if !modelManagerState.isModelInitialized(model) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainUi(model: model)
            }

            // Resetting engine overlay.
            if viewModel.uiState.resettingEngine {
                ZStack {
                    colors.surface.ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(Str.resettingEngine)
                            .foregroundColor(colors.onSurfaceVariant)
                        Text(Str.reinitializingDescription)
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(colors.onSurfaceVariant.opacity(0.7))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Conversation history panel — slides up from bottom.
            if showConversationHistoryPanel {
                ConversationHistoryPanel(
                    task: task,
                    bottomPadding: bottomPadding,
                    viewModel: viewModel,
                    onDismiss: { showConversationHistoryPanel = false }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
                .onChange(of: showConversationHistoryPanel) { visible in
                    setTopBarVisible(!visible)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.uiState.resettingEngine)
        .animation(.easeInOut(duration: 0.25), value: showConversationHistoryPanel)
        .background(colors.surface)
        .alert(Str.error, isPresented: $showErrorDialog) {
            Button(Str.cancel, role: .cancel) { showErrorDialog = false }
            Button(Str.reset) {
                showErrorDialog = false
                viewModel.resetEngine(model: modelManagerViewModel.uiState.selectedModel,
                                       tools: tools,
                                       onError: { err in
                    errorDialogContent = err
                    showErrorDialog = true
                })
            }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorDialogContent)
                Text(Str.resetNote)
                    .foregroundColor(customColors.warningTextColor)
                    .font(AppTypography.labelMedium)
            }
        }
        // Observe command flow (tool call results from the model).
        .task {
            for await command in commandFlow {
                await handleCommand(command)
            }
        }
    }

    // MARK: - Main UI

    @ViewBuilder
    private func mainUi(model: Model) -> some View {
        VStack(spacing: 0) {
            // WebView — hosts the TinyGarden JS game.
            ZStack(alignment: .bottom) {
                TinyGardenWebView { wv in
                    webView = wv

                    // Show tutorial on first launch.
                    if !viewModel.dataStoreRepository.getHasRunTinyGarden() {
                        viewModel.dataStoreRepository.setHasRunTinyGarden(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            wv.evaluateJavaScript("tinyGarden.showHelp()", completionHandler: nil)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            // Text input row.
            HStack(spacing: 4) {
                TextField(Str.chatTextinputPlaceholder, text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(viewModel.uiState.processing)
                    .padding(.leading, 16)

                // Loading / history button.
                if viewModel.uiState.processing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 48, height: 48)
                        .padding(.trailing, 8)
                } else {
                    Button {
                        showConversationHistoryPanel = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundColor(colors.onSurface)
                    }
                    .frame(width: 48, height: 48)
                    .padding(.trailing, 8)
                }

                // Send button.
                Button {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    inputText = ""
                    processInstructionText(text, model: model)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.uiState.processing)
                .padding(.trailing, 16)
            }
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
        }
    }

    // MARK: - Process instruction

    private func processInstructionText(_ text: String, model: Model) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Secret unlock cheat code — mirrors Android SHA-256 check.
        let hash = sha256Base64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if hash == "XtNztQDSDvVpMRPOK+q9tZs43x/VD1teVs3CvWp7zkc=" {
            webView?.evaluateJavaScript("tinyGarden.unlockAll()", completionHandler: nil)
            return
        }

        viewModel.getCommand(
            model: model,
            instructionText: text,
            onDone: { [weak vm = viewModel] response in
                guard let vm = vm else { return }
                // If the last message is not from the agent (no function was called), add a warning.
                if vm.uiState.messages.last?.side != .agent {
                    vm.addMessage(TinyGardenMessage(
                        content: "인식된 함수 호출이 없습니다.",
                        side: .system, isWarning: true))
                }

                // Reset conversation every N turns.
                let numTurnsToReset = model.getIntConfigValue(key: ConfigKeys.RESET_CONVERSATION_TURN_COUNT)
                if vm.uiState.numTurns == numTurnsToReset {
                    vm.resetConversation(
                        model: model,
                        tools: tools,
                        prevSeed: prevSeed,
                        prevPlots: prevPlots,
                        prevAction: prevAction)
                }
            },
            onError: { error in
                errorDialogContent = error
                showErrorDialog = true
            }
        )
    }

    // MARK: - Command handler (mirrors LaunchedEffect commandFlow.collect)

    @MainActor
    private func handleCommand(_ command: TinyGardenCommand) async {
        // Format and add the function call to the conversation history.
        let functionName: String
        switch command.item {
        case TinyGardenItem.sunflower.rawValue + 1,
             TinyGardenItem.daisy.rawValue + 1,
             TinyGardenItem.rose.rawValue + 1,
             TinyGardenItem.special.rawValue + 1:
            functionName = "plantSeed"
        case TinyGardenItem.wateringCan.rawValue + 1:
            functionName = "waterPlots"
        case TinyGardenItem.scythe.rawValue + 1:
            functionName = "harvestPlots"
        default:
            functionName = ""
        }

        let strPlots = "[\(command.plots.map(String.init).joined(separator: ","))]"
        let functionParameter: String
        switch command.item {
        case TinyGardenItem.sunflower.rawValue + 1:   functionParameter = "- seed: \"sunflower\"\n- plots: \(strPlots)"
        case TinyGardenItem.daisy.rawValue + 1:       functionParameter = "- seed: \"daisy\"\n- plots: \(strPlots)"
        case TinyGardenItem.rose.rawValue + 1:        functionParameter = "- seed: \"rose\"\n- plots: \(strPlots)"
        case TinyGardenItem.special.rawValue + 1:     functionParameter = "- seed: \"special\"\n- plots: \(strPlots)"
        case TinyGardenItem.wateringCan.rawValue + 1: functionParameter = "- plots: \(strPlots)"
        case TinyGardenItem.scythe.rawValue + 1:      functionParameter = "- plots: \(strPlots)"
        default: functionParameter = ""
        }

        let numParameters: Int
        switch command.item {
        case TinyGardenItem.wateringCan.rawValue + 1,
             TinyGardenItem.scythe.rawValue + 1: numParameters = 1
        default: numParameters = 2
        }

        let paramLabel = numParameters == 1 ? "Parameter" : "Parameters"
        let msgContent = "**\(Str.functionName)**:\n- \(functionName)\n\n**\(paramLabel)**:\n\(functionParameter)"
        viewModel.addMessage(TinyGardenMessage(content: msgContent, side: .agent))

        // Build the JSON command and pass it to the game WebView.
        // NOTE: This mirrors `webViewRef.evaluateJavascript("tinyGarden.runCommands('$commandJson')")`.
        let commandJson = "[{\"item\": \(command.item), \"plot\":[\(command.plots.map(String.init).joined(separator: ","))]}]"
        let js = "tinyGarden.runCommands('\(commandJson)')"
        webView?.evaluateJavaScript(js, completionHandler: nil)

        // Save for conversation reset context.
        prevSeed = {
            switch command.item {
            case TinyGardenItem.sunflower.rawValue + 1:   return TinyGardenItem.sunflower.label
            case TinyGardenItem.daisy.rawValue + 1:       return TinyGardenItem.daisy.label
            case TinyGardenItem.rose.rawValue + 1:        return TinyGardenItem.rose.label
            case TinyGardenItem.special.rawValue + 1:     return TinyGardenItem.special.label
            default: return ""
            }
        }()
        prevPlots = command.plots.map(String.init).joined(separator: ",")
        prevAction = {
            switch command.item {
            case TinyGardenItem.wateringCan.rawValue + 1: return TinyGardenItem.wateringCan.label
            case TinyGardenItem.scythe.rawValue + 1:      return TinyGardenItem.scythe.label
            default: return ""
            }
        }()
    }

    // MARK: - SHA-256 helper

    private func sha256Base64(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Model config helper
private extension Model {
    func getIntConfigValue(key: ConfigKey) -> Int {
        let val = configValues[key.label]
        return convertValueToTargetType(value: val ?? key, valueType: .int) as? Int ?? 0
    }
}
