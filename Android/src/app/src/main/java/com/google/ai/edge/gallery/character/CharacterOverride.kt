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

package com.google.ai.edge.gallery.character

/**
 * A user's per-character customization. Every field is optional; a null field falls back to the
 * built-in [Character] value. Persisted as JSON by [CharacterRepository] and merged onto the base
 * character by [applyOverride], so the customized values flow into the system prompt and the whole
 * UI automatically.
 */
data class CharacterOverride(
  val name: String? = null,
  val tagline: String? = null,
  val intro: String? = null,
  val personality: String? = null,
  val tone: String? = null,
  val topics: List<String>? = null,
  val starters: List<String>? = null,
  /** User-picked still photo (avatar/poster) as a content/file URI string. */
  val imageUri: String? = null,
  /** Background media kind: one of "image", "gif", "video", "lottie". */
  val backgroundKind: String? = null,
  /** Background media URI string (paired with [backgroundKind]). */
  val backgroundUri: String? = null,
  /**
   * Chat-background focus (crop alignment) bias in [-1, 1]: x = -1 left … +1 right, y = -1 top …
   * +1 bottom. Set by dragging the background. Null = default (top-center).
   */
  val bgFocusX: Float? = null,
  val bgFocusY: Float? = null,
  /** Chat-background zoom (pinch). 1.0 = fit-fill, >1 zoomed in. Null = default (1.0). */
  val bgZoom: Float? = null,
) {
  /** True when nothing has been customized (used to drop empty overrides). */
  val isEmpty: Boolean
    get() =
      name == null &&
        tagline == null &&
        intro == null &&
        personality == null &&
        tone == null &&
        topics == null &&
        starters == null &&
        imageUri == null &&
        backgroundUri == null &&
        bgFocusX == null &&
        bgFocusY == null &&
        bgZoom == null
}

/** Builds a [CharacterBackground] from a persisted kind + media source. */
fun characterBackgroundOf(kind: String, source: MediaSource): CharacterBackground =
  when (kind) {
    "gif" -> CharacterBackground.Gif(source)
    "video" -> CharacterBackground.Video(source)
    "lottie" -> CharacterBackground.Lottie(source)
    else -> CharacterBackground.StaticImage(source)
  }

/**
 * Returns this character with [override] applied. Null/blank override fields keep the built-in
 * values, so editing just one field changes just that. The avatar still photo and the background are
 * independent: changing one doesn't touch the other.
 */
fun Character.applyOverride(override: CharacterOverride?): Character {
  if (override == null) return this
  val newBackground =
    if (override.backgroundUri != null && override.backgroundKind != null) {
      characterBackgroundOf(override.backgroundKind, MediaSource.Uri(override.backgroundUri))
    } else {
      background
    }
  return copy(
    name = override.name ?: name,
    tagline = override.tagline ?: tagline,
    intro = override.intro ?: intro,
    personality = override.personality ?: personality,
    tone = override.tone ?: tone,
    topics = override.topics ?: topics,
    starters = override.starters ?: starters,
    imageUri = override.imageUri ?: imageUri,
    background = newBackground,
  )
}
