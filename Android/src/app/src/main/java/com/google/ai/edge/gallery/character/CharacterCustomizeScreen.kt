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

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceOption
import com.google.ai.edge.gallery.ui.mainpage.CharacterBackgroundView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val ScrimBase = Color(0xFF140A2B)
private val AccentPurple = Color(0xFF7C4DFF)
private val AccentPink = Color(0xFFE15BD0)

/**
 * Full-screen editor for every property of a character: still photo, background media, name,
 * tagline, intro, personality, tone (instructions), topics (tags), greetings and voice. Saving
 * stores a [CharacterOverride] which is merged onto the base character everywhere — including the
 * LLM system prompt — so the edits take effect immediately and persist.
 *
 * [character] is the current (already-merged) character used to pre-fill the form; [override] is the
 * saved customization (for media pre-fill).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CharacterCustomizeScreen(
  character: Character,
  override: CharacterOverride?,
  voices: List<VoiceOption>,
  selectedVoiceId: String,
  onSelectVoice: (String) -> Unit,
  onSave: (CharacterOverride) -> Unit,
  onResetDefaults: () -> Unit,
  onClose: () -> Unit,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()

  var name by remember { mutableStateOf(character.name) }
  var tagline by remember { mutableStateOf(character.tagline) }
  var intro by remember { mutableStateOf(character.intro) }
  var personality by remember { mutableStateOf(character.personality) }
  var tone by remember { mutableStateOf(character.tone) }
  var topics by remember { mutableStateOf(character.topics.joinToString(", ")) }
  var starters by remember { mutableStateOf(character.starters.joinToString("\n")) }
  var stillUri by remember { mutableStateOf(override?.imageUri) }
  var bgUri by remember { mutableStateOf(override?.backgroundUri) }
  var bgKind by remember { mutableStateOf(override?.backgroundKind) }

  val pickStill =
    rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
      if (uri != null) {
        scope.launch {
          val path =
            withContext(Dispatchers.IO) {
              CharacterMediaStore.copyToInternal(context, uri, character.id, "still")
            }
          if (path != null) stillUri = path
        }
      }
    }
  val pickBg =
    rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
      if (uri != null) {
        val kind = CharacterMediaStore.mediaKind(context, uri)
        scope.launch {
          val path =
            withContext(Dispatchers.IO) {
              CharacterMediaStore.copyToInternal(context, uri, character.id, "bg")
            }
          if (path != null) {
            bgUri = path
            bgKind = kind
          }
        }
      }
    }

  fun buildOverride(): CharacterOverride =
    CharacterOverride(
      name = name.trim().takeIf { it.isNotBlank() },
      tagline = tagline.trim().takeIf { it.isNotBlank() },
      intro = intro.trim().takeIf { it.isNotBlank() },
      personality = personality.trim().takeIf { it.isNotBlank() },
      tone = tone.trim().takeIf { it.isNotBlank() },
      topics = topics.split(",").map { it.trim() }.filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() },
      starters =
        starters.split("\n").map { it.trim() }.filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() },
      imageUri = stillUri,
      backgroundKind = bgKind,
      backgroundUri = bgUri,
    )

  Box(modifier = Modifier.fillMaxSize().background(ScrimBase)) {
    Column(
      modifier =
        Modifier.fillMaxSize()
          .systemBarsPadding()
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 20.dp, vertical = 12.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      // Header.
      Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onClose) {
          Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "닫기", tint = Color.White)
        }
        Text(
          "캐릭터 편집",
          color = Color.White,
          fontWeight = FontWeight.Bold,
          fontSize = 20.sp,
          modifier = Modifier.weight(1f).padding(start = 4.dp),
        )
        Text(
          "기본값으로",
          color = AccentPink,
          fontSize = 14.sp,
          fontWeight = FontWeight.Medium,
          modifier = Modifier.clickable { onResetDefaults() }.padding(8.dp),
        )
      }

      // Media: still photo + background, side by side.
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        MediaTile(
          label = "프로필 사진",
          onChange = {
            pickStill.launch(
              PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
            )
          },
          modifier = Modifier.weight(1f),
        ) {
          if (stillUri != null) {
            AsyncImage(
              model = stillUri,
              contentDescription = null,
              contentScale = ContentScale.Crop,
              modifier = Modifier.fillMaxSize(),
            )
          } else {
            Image(
              painter = painterResource(character.imageRes),
              contentDescription = null,
              contentScale = ContentScale.Crop,
              modifier = Modifier.fillMaxSize(),
            )
          }
        }
        MediaTile(
          label = "배경 (사진·움짤·영상)",
          onChange = {
            pickBg.launch(
              PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
            )
          },
          modifier = Modifier.weight(1f),
        ) {
          val previewBg =
            if (bgUri != null && bgKind != null) {
              characterBackgroundOf(bgKind!!, MediaSource.Uri(bgUri!!))
            } else {
              character.background
            }
          CharacterBackgroundView(
            background = previewBg,
            playing = true,
            contentDescription = null,
            alignment = Alignment.Center,
          )
        }
      }

      // Text fields.
      EditField("이름", name, { name = it }, singleLine = true)
      EditField("한 줄 소개", tagline, { tagline = it }, singleLine = true)
      EditField("소개", intro, { intro = it }, minLines = 2)
      EditField("성격", personality, { personality = it }, minLines = 2)
      EditField("말투·지시어 (AI에게 주는 지침)", tone, { tone = it }, minLines = 2)
      EditField("관심 주제 (쉼표로 구분)", topics, { topics = it })
      EditField("인사말 (줄바꿈으로 구분)", starters, { starters = it }, minLines = 3)

      // Voice.
      Text("목소리", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
      if (voices.isEmpty()) {
        Text("음성을 준비하는 중이에요…", color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp)
      } else {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          voices.forEach { voice ->
            val selected = voice.id == selectedVoiceId
            Box(
              modifier =
                Modifier.clip(RoundedCornerShape(50))
                  .background(if (selected) AccentPurple else Color.White.copy(alpha = 0.14f))
                  .clickable { onSelectVoice(voice.id) }
                  .padding(horizontal = 14.dp, vertical = 8.dp)
            ) {
              Text(voice.label, color = Color.White, fontSize = 13.sp)
            }
          }
        }
      }

      Spacer(modifier = Modifier.height(4.dp))

      // Save.
      Box(
        modifier =
          Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
            .clickable { onSave(buildOverride()) }
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center,
      ) {
        Text("저장", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
      }
      Spacer(modifier = Modifier.height(12.dp))
    }
  }
}

/** A media preview tile with a "변경" (change) affordance over it. */
@Composable
private fun MediaTile(
  label: String,
  onChange: () -> Unit,
  modifier: Modifier = Modifier,
  content: @Composable () -> Unit,
) {
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
    Text(label, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
    Box(
      modifier =
        Modifier.fillMaxWidth()
          .aspectRatio(0.74f)
          .clip(RoundedCornerShape(16.dp))
          .background(Color.White.copy(alpha = 0.08f))
          .clickable { onChange() }
    ) {
      content()
      // "Change" pill bottom-center.
      Row(
        modifier =
          Modifier.align(Alignment.BottomCenter)
            .padding(8.dp)
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.55f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Icon(
          Icons.Rounded.PhotoCamera,
          contentDescription = null,
          tint = Color.White,
          modifier = Modifier.size(15.dp),
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text("변경", color = Color.White, fontSize = 12.sp)
      }
    }
  }
}

@Composable
private fun EditField(
  label: String,
  value: String,
  onValueChange: (String) -> Unit,
  singleLine: Boolean = false,
  minLines: Int = 1,
) {
  OutlinedTextField(
    value = value,
    onValueChange = onValueChange,
    label = { Text(label) },
    singleLine = singleLine,
    minLines = minLines,
    modifier = Modifier.fillMaxWidth(),
    colors =
      OutlinedTextFieldDefaults.colors(
        focusedTextColor = Color.White,
        unfocusedTextColor = Color.White,
        focusedBorderColor = AccentPurple,
        unfocusedBorderColor = Color.White.copy(alpha = 0.25f),
        focusedLabelColor = AccentPink,
        unfocusedLabelColor = Color.White.copy(alpha = 0.6f),
        cursorColor = AccentPink,
        focusedContainerColor = Color.White.copy(alpha = 0.05f),
        unfocusedContainerColor = Color.White.copy(alpha = 0.05f),
      ),
  )
}
