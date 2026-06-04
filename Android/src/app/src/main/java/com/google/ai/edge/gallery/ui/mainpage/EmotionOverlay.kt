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

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.sp
import com.google.ai.edge.gallery.customtasks.voiceassistant.EmotionCue
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.delay

/**
 * A non-interactive overlay that plays a brief, delightful "emotion" effect — emoji that float up,
 * pop and fade — whenever the assistant's reply contains emoji (instead of reading them aloud). It's
 * meant to make the conversation feel more like an emotional exchange, similar to the floating
 * reactions in modern video-call apps.
 */
@Composable
fun EmotionOverlay(cue: EmotionCue?, modifier: Modifier = Modifier) {
  if (cue == null || cue.emojis.isEmpty()) return
  BoxWithConstraints(modifier = modifier.fillMaxSize()) {
    val widthPx = constraints.maxWidth.toFloat()
    val heightPx = constraints.maxHeight.toFloat()
    // Restart the whole burst when a new cue arrives.
    key(cue.id) { EmotionBurst(emojis = cue.emojis, widthPx = widthPx, heightPx = heightPx) }
  }
}

private data class Particle(
  val emoji: String,
  val startXFraction: Float,
  val driftXPx: Float,
  val swayPx: Float,
  val sizeSp: Int,
  val delayMs: Long,
  val durationMs: Int,
  val rotationDeg: Float,
)

@Composable
private fun EmotionBurst(emojis: List<String>, widthPx: Float, heightPx: Float) {
  val particles =
    remember(emojis, widthPx) {
      val count = 12
      List(count) { i ->
        Particle(
          emoji = emojis[i % emojis.size],
          startXFraction = 0.18f + Random.nextFloat() * 0.64f,
          driftXPx = (Random.nextFloat() - 0.5f) * widthPx * 0.22f,
          swayPx = (12f + Random.nextFloat() * 18f) * (if (Random.nextBoolean()) 1f else -1f),
          sizeSp = (26 + Random.nextInt(22)),
          delayMs = (i * 60 + Random.nextInt(140)).toLong(),
          durationMs = 1500 + Random.nextInt(900),
          rotationDeg = (Random.nextFloat() - 0.5f) * 36f,
        )
      }
    }
  for (p in particles) {
    EmotionParticle(p, widthPx, heightPx)
  }
}

@Composable
private fun EmotionParticle(p: Particle, widthPx: Float, heightPx: Float) {
  val progress = remember { Animatable(0f) }
  LaunchedEffect(Unit) {
    delay(p.delayMs)
    progress.animateTo(1f, animationSpec = tween(durationMillis = p.durationMs, easing = LinearOutSlowInEasing))
  }
  val t = progress.value

  // Fade in quickly, hold, then fade out near the end.
  val alpha =
    when {
      t < 0.12f -> t / 0.12f
      t > 0.7f -> ((1f - t) / 0.3f).coerceIn(0f, 1f)
      else -> 1f
    }
  // Pop in, then settle slightly smaller.
  val scale =
    if (t < 0.25f) lerp(0.5f, 1.15f, t / 0.25f) else lerp(1.15f, 0.92f, (t - 0.25f) / 0.75f)

  // Rise from the lower third toward the upper area, with a gentle horizontal sway.
  val startY = heightPx * 0.72f
  val rise = heightPx * 0.52f
  val y = startY - rise * t
  val x = widthPx * p.startXFraction + p.driftXPx * t + sin(t.toDouble() * PI * 2).toFloat() * p.swayPx

  Text(
    text = p.emoji,
    fontSize = p.sizeSp.sp,
    modifier =
      Modifier.graphicsLayer {
        translationX = x
        translationY = y
        this.alpha = alpha
        scaleX = scale
        scaleY = scale
        rotationZ = p.rotationDeg * t
      },
  )
}

private fun lerp(start: Float, stop: Float, fraction: Float): Float =
  start + (stop - start) * fraction.coerceIn(0f, 1f)
