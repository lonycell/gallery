// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/EmotionText.kt

import Foundation

/// A one-shot cue to play an emotion effect (floating emoji) on the chat screen,
/// emitted when an assistant reply contains emoji. The `id` makes each cue unique
/// so identical emoji re-trigger the animation.
struct EmotionCue {
    let emojis: [String]
    let id: Int64
}

// MARK: - TTS text sanitization

/// Removes fenced and inline code blocks from `text` so they are never read aloud.
func stripCodeForSpeech(_ text: String) -> String {
    let fenced = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
    let inline = try? NSRegularExpression(pattern: "`[^`\\n]*`", options: [])
    var result = text
    let range = NSRange(result.startIndex..., in: result)
    result = fenced?.stringByReplacingMatches(in: result, range: range, withTemplate: " ") ?? result
    let range2 = NSRange(result.startIndex..., in: result)
    result = inline?.stringByReplacingMatches(in: result, range: range2, withTemplate: " ") ?? result
    return result
}

/// Returns the part of a still-streaming reply that is safe to speak:
/// complete fenced code blocks are removed; an open (not-yet-closed) fence —
/// plus everything after it — is held back. Mirrors `speakableStreamingView`.
func speakableStreamingView(_ full: String) -> String {
    let fenced = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
    let range = NSRange(full.startIndex..., in: full)
    var withoutClosed = fenced?.stringByReplacingMatches(in: full, range: range, withTemplate: " ") ?? full
    if let openRange = withoutClosed.range(of: "```") {
        withoutClosed = String(withoutClosed[withoutClosed.startIndex..<openRange.lowerBound])
    }
    let inlineRange = NSRange(withoutClosed.startIndex..., in: withoutClosed)
    let inline = try? NSRegularExpression(pattern: "`[^`\\n]*`", options: [])
    return inline?.stringByReplacingMatches(in: withoutClosed, range: inlineRange, withTemplate: " ") ?? withoutClosed
}

/// Returns `text` cleaned for TTS: code, emoji, pictographs and markdown removed
/// and whitespace collapsed. May return an empty string.
func sanitizeForSpeech(_ text: String) -> String {
    var result = stripCodeForSpeech(text)
    // Strip emoji/pictographic Unicode ranges. Swift's Character.isEmoji would
    // miss some ranges; we remove by Unicode scalar value instead.
    result = result.unicodeScalars.filter { scalar in
        let v = scalar.value
        // Emoji + symbols ranges (mirrors Android SPEECH_SYMBOL_RANGES).
        let isSymbol =
            (v >= 0x1F000 && v <= 0x1FAFF) ||
            (v >= 0x2600  && v <= 0x27BF)  ||
            (v >= 0x2B00  && v <= 0x2BFF)  ||
            (v >= 0x1F1E6 && v <= 0x1F1FF) ||
            (v >= 0x2300  && v <= 0x23FF)  ||
            (v >= 0x2500  && v <= 0x25FF)  ||
            (v >= 0x2190  && v <= 0x21FF)  ||
            (v >= 0x1F3FB && v <= 0x1F3FF) ||
            (v >= 0xFE00  && v <= 0xFE0F)  ||
            v == 0x200D || v == 0x20E3
        return !isSymbol
    }.reduce("") { $0 + String($1) }
    // Strip markdown punctuation that sounds odd when read aloud.
    let mdRegex = try? NSRegularExpression(pattern: "[*_#`~|>\\\\^•]", options: [])
    let r = NSRange(result.startIndex..., in: result)
    result = mdRegex?.stringByReplacingMatches(in: result, range: r, withTemplate: " ") ?? result
    // Collapse whitespace.
    let wsRegex = try? NSRegularExpression(pattern: "\\s+", options: [])
    let r2 = NSRange(result.startIndex..., in: result)
    result = wsRegex?.stringByReplacingMatches(in: result, range: r2, withTemplate: " ") ?? result
    return result.trimmingCharacters(in: .whitespaces)
}

// MARK: - Emoji extraction for the visual emotion effect

/// Extracts emoji clusters from `text` for the floating emotion animation.
func extractEmojis(_ text: String) -> [String] {
    // Conservative emoji ranges (avoids arrows / geometric symbols).
    let pattern = "[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F1E6}-\u{1F1FF}]" +
                  "(?:[\u{1F3FB}-\u{1F3FF}\u{FE0F}\u{200D}" +
                  "\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F1E6}-\u{1F1FF}])*"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        Range(match.range, in: text).map { String(text[$0]) }
    }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}
