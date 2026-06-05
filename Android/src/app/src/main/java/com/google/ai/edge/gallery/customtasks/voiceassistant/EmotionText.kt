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

package com.google.ai.edge.gallery.customtasks.voiceassistant

/**
 * A one-shot cue to play an emotion effect (floating emoji) on the chat screen, emitted when an
 * assistant reply contains emoji. The [id] makes each cue unique so identical emoji re-trigger.
 */
data class EmotionCue(val emojis: List<String>, val id: Long)

// Broad set of emoji / pictographic / symbol ranges (plus variation selectors, ZWJ, skin tones,
// keycap) — stripped from text before TTS so the engine doesn't read them aloud awkwardly.
private val SPEECH_SYMBOL_RANGES =
  "\\x{1F000}-\\x{1FAFF}" +
    "\\x{2600}-\\x{27BF}" +
    "\\x{2B00}-\\x{2BFF}" +
    "\\x{1F1E6}-\\x{1F1FF}" +
    "\\x{2300}-\\x{23FF}" +
    "\\x{2500}-\\x{25FF}" +
    "\\x{2190}-\\x{21FF}" +
    "\\x{1F3FB}-\\x{1F3FF}" +
    "\\x{FE00}-\\x{FE0F}" +
    "\\x{200D}" +
    "\\x{20E3}"

private val speechSymbolRegex = Regex("[$SPEECH_SYMBOL_RANGES]")
// Markdown / read-aloud-unfriendly punctuation to drop (keeps normal sentence punctuation).
private val markdownRegex = Regex("[*_#`~|>\\\\^•]")
private val whitespaceRegex = Regex("\\s+")

// A complete fenced code block: ```lang\n ... ``` (optional language, multiline body). Removed from
// spoken text entirely so the engine never reads code aloud.
private val fencedCodeRegex = Regex("```[\\s\\S]*?```")
// Inline code: `code` (single backticks, no newline inside).
private val inlineCodeRegex = Regex("`[^`\\n]*`")

/**
 * Removes code from [text] so it is never read aloud: complete fenced code blocks and inline code
 * are dropped. Used by both the after-complete and streaming TTS paths. The on-screen text is left
 * untouched — only the spoken version loses the code.
 */
fun stripCodeForSpeech(text: String): String =
  text.replace(fencedCodeRegex, " ").replace(inlineCodeRegex, " ")

/**
 * Returns the portion of a still-streaming reply [full] that is safe to speak: complete fenced code
 * blocks are removed, and an *open* (not-yet-closed) fence — plus everything after it — is held back
 * so a half-streamed code block is never spoken. Once the fence closes it is dropped by
 * [stripCodeForSpeech]. The returned prefix is stable across calls (closed/removed blocks don't shift
 * the already-spoken prefix), so callers can track spoken position against it.
 */
fun speakableStreamingView(full: String): String {
  // Count fences; an odd count means the last one is still open.
  val withoutClosed = full.replace(fencedCodeRegex, " ")
  val openFence = withoutClosed.indexOf("```")
  val held = if (openFence >= 0) withoutClosed.substring(0, openFence) else withoutClosed
  return held.replace(inlineCodeRegex, " ")
}

/**
 * Returns [text] cleaned for text-to-speech: code, emoji, pictographs and markdown symbols removed
 * and whitespace collapsed, so the spoken reply sounds natural. May return an empty string (e.g. a
 * reply that was only code or an emoji) — callers should skip speaking in that case.
 */
fun sanitizeForSpeech(text: String): String =
  stripCodeForSpeech(text)
    .replace(speechSymbolRegex, " ")
    .replace(markdownRegex, " ")
    .replace(whitespaceRegex, " ")
    .trim()

// Conservative emoji ranges used to drive the visual effect (avoids arrows / geometric symbols).
private val EMOJI_ANIM_RANGES =
  "\\x{1F300}-\\x{1FAFF}" + "\\x{2600}-\\x{27BF}" + "\\x{2B00}-\\x{2BFF}" + "\\x{1F1E6}-\\x{1F1FF}"

private val emojiClusterRegex =
  Regex("[$EMOJI_ANIM_RANGES](?:[\\x{1F3FB}-\\x{1F3FF}\\x{FE0F}\\x{200D}$EMOJI_ANIM_RANGES])*")

/** Extracts emoji (as grapheme-ish clusters) from [text], for the emotion effect. */
fun extractEmojis(text: String): List<String> =
  emojiClusterRegex.findAll(text).map { it.value }.filter { it.isNotBlank() }.toList()
