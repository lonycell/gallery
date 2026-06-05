/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/PromptTemplateConfigs.kt
//
// Defines the prompt-template types used by the LLM Prompt Lab single-turn
// screen. Each template carries a label, optional input editors (e.g. a tone
// selector), example prompts, and a closure that builds the full prompt string
// from the user's raw input and editor selections.

import SwiftUI

// MARK: - Input editor types

enum PromptTemplateInputEditorType {
  case singleSelect
}

enum RewriteToneType: String, CaseIterable {
  case formal       = "Formal"
  case casual       = "Casual"
  case friendly     = "Friendly"
  case polite       = "Polite"
  case enthusiastic = "Enthusiastic"
  case concise      = "Concise"

  var label: String { rawValue }
}

enum SummarizationType: String, CaseIterable {
  case keyBulletPoint    = "Key bullet points (3-5)"
  case shortParagraph    = "Short paragraph (1-2 sentences)"
  case conciseSummary    = "Concise summary (~50 words)"
  case headlineTitle     = "Headline / title"
  case oneSentenceSummary = "One-sentence summary"

  var label: String { rawValue }
}

enum LanguageType: String, CaseIterable {
  case cpp        = "C++"
  case java       = "Java"
  case javascript = "JavaScript"
  case kotlin     = "Kotlin"
  case python     = "Python"
  case swift      = "Swift"
  case typescript = "TypeScript"

  var label: String { rawValue }
}

enum InputEditorLabel: String {
  case tone     = "Tone"
  case style    = "Style"
  case language = "Language"
}

// MARK: - Input editor models

class PromptTemplateInputEditor {
  let label: String
  let type: PromptTemplateInputEditorType
  let defaultOption: String

  init(label: String, type: PromptTemplateInputEditorType, defaultOption: String = "") {
    self.label = label
    self.type = type
    self.defaultOption = defaultOption
  }
}

/// Single-select drop-down editor. Mirrors `PromptTemplateSingleSelectInputEditor`.
final class PromptTemplateSingleSelectInputEditor: PromptTemplateInputEditor {
  let options: [String]

  init(label: String, options: [String], defaultOption: String = "") {
    self.options = options
    super.init(label: label, type: .singleSelect, defaultOption: defaultOption)
  }
}

struct PromptTemplateConfig {
  let inputEditors: [PromptTemplateInputEditor]
  init(inputEditors: [PromptTemplateInputEditor] = []) { self.inputEditors = inputEditors }
}

// MARK: - Gradient style helper (mirrors GEMINI_GRADIENT_STYLE)

let geminiGradientColors: [Color] = [
  Color(red: 0x42/255, green: 0x85/255, blue: 0xF4/255),
  Color(red: 0x9B/255, green: 0x72/255, blue: 0xCB/255),
  Color(red: 0xD9/255, green: 0x65/255, blue: 0x70/255),
]

// MARK: - PromptTemplateType

/// Each case defines a template label, optional input editors, a full-prompt
/// generator, and a set of example prompts. Mirrors `enum PromptTemplateType`.
enum PromptTemplateType: CaseIterable, Identifiable {
  case freeForm
  case rewriteTone
  case summarizeText
  case codeSnippet

  var id: String { label }

  var label: String {
    switch self {
    case .freeForm:      return "Free form"
    case .rewriteTone:   return "Rewrite tone"
    case .summarizeText: return "Summarize text"
    case .codeSnippet:   return "Code snippet"
    }
  }

  var config: PromptTemplateConfig {
    switch self {
    case .freeForm:
      return PromptTemplateConfig()
    case .rewriteTone:
      return PromptTemplateConfig(inputEditors: [
        PromptTemplateSingleSelectInputEditor(
          label: InputEditorLabel.tone.rawValue,
          options: RewriteToneType.allCases.map { $0.label },
          defaultOption: RewriteToneType.formal.label)
      ])
    case .summarizeText:
      return PromptTemplateConfig(inputEditors: [
        PromptTemplateSingleSelectInputEditor(
          label: InputEditorLabel.style.rawValue,
          options: SummarizationType.allCases.map { $0.label },
          defaultOption: SummarizationType.keyBulletPoint.label)
      ])
    case .codeSnippet:
      return PromptTemplateConfig(inputEditors: [
        PromptTemplateSingleSelectInputEditor(
          label: InputEditorLabel.language.rawValue,
          options: LanguageType.allCases.map { $0.label },
          defaultOption: LanguageType.javascript.label)
      ])
    }
  }

  /// Generates the full prompt string from user input + editor selections.
  func genFullPrompt(userInput: String, inputEditorValues: [String: String]) -> String {
    switch self {
    case .freeForm:
      return userInput
    case .rewriteTone:
      let tone = inputEditorValues[InputEditorLabel.tone.rawValue] ?? RewriteToneType.formal.label
      return "Rewrite the following text using a \(tone.lowercased()) tone: \(userInput)"
    case .summarizeText:
      let style = inputEditorValues[InputEditorLabel.style.rawValue] ?? SummarizationType.keyBulletPoint.label
      return "Please summarize the following in \(style.lowercased()): \(userInput)"
    case .codeSnippet:
      let language = inputEditorValues[InputEditorLabel.language.rawValue] ?? LanguageType.javascript.label
      return "Write a \(language) code snippet to \(userInput)"
    }
  }

  /// The gradient-prefix portion of the prompt (displayed in a tinted colour).
  /// Used for the "preview prompt" mode in PromptTemplatesPanel.
  func genPromptPrefix(inputEditorValues: [String: String]) -> String {
    switch self {
    case .freeForm:
      return ""
    case .rewriteTone:
      let tone = inputEditorValues[InputEditorLabel.tone.rawValue] ?? RewriteToneType.formal.label
      return "Rewrite the following text using a \(tone.lowercased()) tone: "
    case .summarizeText:
      let style = inputEditorValues[InputEditorLabel.style.rawValue] ?? SummarizationType.keyBulletPoint.label
      return "Please summarize the following in \(style.lowercased()): "
    case .codeSnippet:
      let language = inputEditorValues[InputEditorLabel.language.rawValue] ?? LanguageType.javascript.label
      return "Write a \(language) code snippet to "
    }
  }

  var examplePrompts: [String] {
    switch self {
    case .freeForm:
      return [
        "Suggest 3 topics for a podcast about \"Friendships in your 20s\".",
        "Outline the key sections needed in a basic logo design brief.",
        "List 3 pros and 3 cons to consider before buying a smart watch.",
        "Write a short, optimistic quote about the future of technology.",
        "Generate 3 potential names for a mobile app that helps users identify plants.",
        "Explain the difference between AI and machine learning in 2 sentences.",
        "Create a simple haiku about a cat sleeping in the sun.",
        "List 3 ways to make instant noodles taste better using common kitchen ingredients.",
      ]
    case .rewriteTone:
      return [
        "Hey team, just wanted to remind everyone about the meeting tomorrow @ 10. Be there!",
        "Our new software update includes several bug fixes and performance improvements.",
        "Due to the fact that the weather was bad, we decided to postpone the event.",
        "Please find attached the requested documentation for your perusal.",
        "Welcome to the team. Review the onboarding materials.",
      ]
    case .summarizeText:
      return [
        "The new Pixel phone features an advanced camera system with improved low-light performance and AI-powered editing tools. The display is brighter and more energy-efficient. It runs on the latest Tensor chip, offering faster processing and enhanced security features. Battery life has also been extended, providing all-day power for most users.",
        "Beginning this Friday, January 24, giant pandas Bao Li and Qing Bao are officially on view to the public at the Smithsonian's National Zoo and Conservation Biology Institute (NZCBI). The 3-year-old bears arrived in Washington this past October, undergoing a quarantine period before making their debut. Under NZCBI's new agreement with the CWCA, Qing Bao and Bao Li will remain in the United States for ten years, until April 2034, in exchange for an annual fee of $1 million.",
      ]
    case .codeSnippet:
      return [
        "Create an alert box that says \"Hello, World!\"",
        "Declare an immutable variable named 'appName' with the value \"AI Gallery\"",
        "Print the numbers from 1 to 5 using a for loop.",
        "Write a function that returns the square of an integer input.",
      ]
    }
  }
}
