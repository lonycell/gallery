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
 * A flexible reference to a piece of media: either a bundled app resource id (drawable for
 * images/GIFs, raw for videos/Lottie JSON) or a URI/URL string (content://, file://, http(s)://).
 * This lets a character background point at on-device assets now and remote assets later without
 * changing the model.
 */
sealed interface MediaSource {
  /** A bundled resource id — `@DrawableRes` for image/GIF, `@RawRes` for video/Lottie. */
  data class Res(val resId: Int) : MediaSource

  /** A URI or URL string (content://, file://, android.resource://, http(s)://). */
  data class Uri(val uri: String) : MediaSource

  companion object {
    fun res(resId: Int): MediaSource = Res(resId)

    fun uri(uri: String): MediaSource = Uri(uri)
  }
}

/**
 * The visual background shown behind a character's main chat screen. Every variant is rendered with
 * the *same* framing (full-bleed, center-cropped, top-aligned) by `CharacterBackgroundView`, so the
 * interface looks uniform regardless of media type. Animated variants ([Gif], [Video], [Lottie])
 * honour a `playing` flag so playback can be paused/resumed.
 */
sealed interface CharacterBackground {
  val source: MediaSource

  /** A still image (the default — keeps existing behaviour). */
  data class StaticImage(override val source: MediaSource) : CharacterBackground

  /** An animated GIF (decoded + animated via Coil). */
  data class Gif(override val source: MediaSource) : CharacterBackground

  /** A short, silently-looping video (played via Media3 ExoPlayer). */
  data class Video(override val source: MediaSource) : CharacterBackground

  /** A Lottie (bodymovin JSON) animation, looped. */
  data class Lottie(override val source: MediaSource) : CharacterBackground

  /** Whether this background animates (and therefore exposes a play/pause control). */
  val isAnimated: Boolean
    get() = this !is StaticImage

  companion object {
    fun image(resId: Int): CharacterBackground = StaticImage(MediaSource.Res(resId))

    fun image(url: String): CharacterBackground = StaticImage(MediaSource.Uri(url))

    fun gif(resId: Int): CharacterBackground = Gif(MediaSource.Res(resId))

    fun gif(url: String): CharacterBackground = Gif(MediaSource.Uri(url))

    fun video(resId: Int): CharacterBackground = Video(MediaSource.Res(resId))

    fun video(url: String): CharacterBackground = Video(MediaSource.Uri(url))

    fun lottie(resId: Int): CharacterBackground = Lottie(MediaSource.Res(resId))

    fun lottie(url: String): CharacterBackground = Lottie(MediaSource.Uri(url))
  }
}
