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

package com.google.ai.edge.gallery.ui.mainpage

import android.content.Context
import android.graphics.drawable.Animatable
import android.net.Uri
import androidx.annotation.OptIn as AndroidxOptIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.ImageLoader
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter
import coil.decode.ImageDecoderDecoder
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.animateLottieCompositionAsState
import com.airbnb.lottie.compose.rememberLottieComposition
import com.google.ai.edge.gallery.character.CharacterBackground
import com.google.ai.edge.gallery.character.MediaSource

/**
 * Renders a [CharacterBackground] full-bleed with a single, uniform framing (center-cropped,
 * top-aligned) regardless of media type, so static images, GIFs, videos, and Lottie all share the
 * same look. Animated variants honour [playing] so playback can be paused/resumed from one control.
 */
@Composable
fun CharacterBackgroundView(
  background: CharacterBackground,
  playing: Boolean,
  contentDescription: String?,
  modifier: Modifier = Modifier,
  alignment: Alignment = Alignment.TopCenter,
) {
  // Identical frame for every variant — this is what makes the interface feel unified.
  val frame = modifier.fillMaxSize()
  when (background) {
    is CharacterBackground.StaticImage ->
      StaticImageBackground(background.source, contentDescription, alignment, frame)
    is CharacterBackground.Gif ->
      GifBackground(background.source, playing, contentDescription, alignment, frame)
    is CharacterBackground.Video -> VideoBackground(background.source, playing, frame)
    is CharacterBackground.Lottie -> LottieBackground(background.source, playing, alignment, frame)
  }
}

@Composable
private fun StaticImageBackground(
  source: MediaSource,
  contentDescription: String?,
  alignment: Alignment,
  modifier: Modifier,
) {
  // A bundled drawable renders instantly with painterResource (no async decode flash); a URI/URL
  // goes through Coil.
  if (source is MediaSource.Res) {
    Image(
      painter = painterResource(source.resId),
      contentDescription = contentDescription,
      contentScale = ContentScale.Crop,
      alignment = alignment,
      modifier = modifier,
    )
  } else {
    AsyncImage(
      model = source.coilModel(),
      contentDescription = contentDescription,
      contentScale = ContentScale.Crop,
      alignment = alignment,
      modifier = modifier,
    )
  }
}

@Composable
private fun GifBackground(
  source: MediaSource,
  playing: Boolean,
  contentDescription: String?,
  alignment: Alignment,
  modifier: Modifier,
) {
  val context = LocalContext.current
  // GIF decoding needs an ImageLoader with the animated decoder (ImageDecoderDecoder, API 28+).
  val imageLoader =
    remember(context) {
      ImageLoader.Builder(context).components { add(ImageDecoderDecoder.Factory()) }.build()
    }
  val painter = rememberAsyncImagePainter(model = source.coilModel(), imageLoader = imageLoader)
  val state = painter.state
  // Pause/resume the animated drawable to honour [playing].
  LaunchedEffect(state, playing) {
    val drawable = (state as? AsyncImagePainter.State.Success)?.result?.drawable
    if (drawable is Animatable) {
      if (playing) drawable.start() else drawable.stop()
    }
  }
  Image(
    painter = painter,
    contentDescription = contentDescription,
    contentScale = ContentScale.Crop,
    alignment = alignment,
    modifier = modifier,
  )
}

@AndroidxOptIn(UnstableApi::class)
@Composable
private fun VideoBackground(source: MediaSource, playing: Boolean, modifier: Modifier) {
  val context = LocalContext.current
  val uri = remember(source) { source.playerUri(context) }
  val exoPlayer =
    remember(uri) {
      ExoPlayer.Builder(context).build().apply {
        setMediaItem(MediaItem.fromUri(uri))
        repeatMode = Player.REPEAT_MODE_ALL
        volume = 0f // a background loop is always silent
        playWhenReady = true
        prepare()
      }
    }
  LaunchedEffect(playing) { exoPlayer.playWhenReady = playing }
  DisposableEffect(uri) { onDispose { exoPlayer.release() } }
  AndroidView(
    factory = { ctx ->
      PlayerView(ctx).apply {
        player = exoPlayer
        useController = false
        // Crop to fill, matching ContentScale.Crop used by the other variants.
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
      }
    },
    modifier = modifier,
  )
}

@Composable
private fun LottieBackground(
  source: MediaSource,
  playing: Boolean,
  alignment: Alignment,
  modifier: Modifier,
) {
  val composition by rememberLottieComposition(source.lottieSpec())
  val progress by
    animateLottieCompositionAsState(
      composition = composition,
      isPlaying = playing,
      iterations = LottieConstants.IterateForever,
      restartOnPlay = false,
    )
  LottieAnimation(
    composition = composition,
    progress = { progress },
    contentScale = ContentScale.Crop,
    alignment = alignment,
    modifier = modifier,
  )
}

// --- MediaSource adapters for the three rendering backends ---

private fun MediaSource.coilModel(): Any =
  when (this) {
    is MediaSource.Res -> resId
    is MediaSource.Uri -> uri
  }

private fun MediaSource.playerUri(context: Context): Uri =
  when (this) {
    is MediaSource.Res -> Uri.parse("android.resource://${context.packageName}/$resId")
    is MediaSource.Uri -> Uri.parse(uri)
  }

private fun MediaSource.lottieSpec(): LottieCompositionSpec =
  when (this) {
    is MediaSource.Res -> LottieCompositionSpec.RawRes(resId)
    is MediaSource.Uri -> LottieCompositionSpec.Url(uri)
  }
