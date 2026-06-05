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

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.MonetizationOn
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantViewModel
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceOption

private val ScrimBase = Color(0xFF140A2B)
private val AccentPurple = Color(0xFF7C4DFF)
private val AccentPink = Color(0xFFE15BD0)
private val CoinGold = Color(0xFFFFC93C)

/**
 * The character-selection screen: a grid of companion cards. Free characters can be selected
 * directly; locked ones can be unlocked with coins or by subscribing (both simulated and persisted
 * via [CharacterRepository]). Tapping a card opens a full-screen introduction.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CharacterScreen(
  viewModel: CharacterViewModel,
  voiceAssistantViewModel: VoiceAssistantViewModel,
  onStartChat: () -> Unit,
  onOpenSubscription: () -> Unit,
  navigateUp: () -> Unit,
) {
  val state by viewModel.state.collectAsState()
  val vaState by voiceAssistantViewModel.uiState.collectAsState()
  var detail by remember { mutableStateOf<Character?>(null) }

  Scaffold(
    topBar = {
      TopAppBar(
        title = { Text("캐릭터 선택") },
        navigationIcon = {
          IconButton(onClick = navigateUp) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "뒤로")
          }
        },
        actions = {
          if (state.isPro) {
            ProBadge()
            Spacer(modifier = Modifier.width(8.dp))
          }
          CoinPill(coins = state.coins)
          Spacer(modifier = Modifier.width(12.dp))
        },
      )
    }
  ) { innerPadding ->
    LazyVerticalGrid(
      columns = GridCells.Fixed(2),
      modifier = Modifier.padding(innerPadding).fillMaxSize(),
      contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
      horizontalArrangement = Arrangement.spacedBy(12.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      items(viewModel.characters, key = { it.id }) { character ->
        CharacterCard(
          character = character,
          unlocked = viewModel.isUnlocked(character),
          selected = state.selectedId == character.id,
          onClick = { detail = character },
        )
      }
    }
  }

  detail?.let { character ->
    CharacterDetail(
      character = character,
      unlocked = viewModel.isUnlocked(character),
      coins = state.coins,
      voices = vaState.voices,
      selectedVoiceId = state.voiceByCharacter[character.id] ?: "",
      onSelectVoice = { voiceId -> viewModel.setVoiceForCharacter(character.id, voiceId) },
      onDismiss = { detail = null },
      onChat = {
        viewModel.select(character.id)
        viewModel.requestGreeting(character.id)
        detail = null
        onStartChat()
      },
      onUnlockWithCoins = { viewModel.tryUnlockWithCoins(character) },
      onSubscribe = {
        detail = null
        onOpenSubscription()
      },
    )
  }
}

@Composable
private fun CoinPill(coins: Int) {
  Row(
    modifier =
      Modifier.clip(RoundedCornerShape(50))
        .background(MaterialTheme.colorScheme.surfaceVariant)
        .padding(horizontal = 10.dp, vertical = 5.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(Icons.Rounded.MonetizationOn, contentDescription = null, tint = CoinGold, modifier = Modifier.size(18.dp))
    Spacer(modifier = Modifier.width(4.dp))
    Text("$coins", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
  }
}

@Composable
private fun ProBadge() {
  Row(
    modifier =
      Modifier.clip(RoundedCornerShape(50))
        .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
        .padding(horizontal = 10.dp, vertical = 5.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(Icons.Rounded.WorkspacePremium, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
    Spacer(modifier = Modifier.width(4.dp))
    Text("PRO", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
  }
}

@Composable
private fun CharacterCard(
  character: Character,
  unlocked: Boolean,
  selected: Boolean,
  onClick: () -> Unit,
) {
  Box(
    modifier =
      Modifier.fillMaxWidth()
        .aspectRatio(0.74f)
        .clip(RoundedCornerShape(20.dp))
        .then(
          if (selected) Modifier.border(2.5.dp, AccentPink, RoundedCornerShape(20.dp))
          else Modifier
        )
        .clickable { onClick() }
  ) {
    Image(
      painter = painterResource(character.imageRes),
      contentDescription = character.name,
      contentScale = ContentScale.Crop,
      modifier = Modifier.fillMaxSize(),
    )
    // Bottom scrim for the name.
    Box(
      modifier =
        Modifier.fillMaxSize()
          .background(
            Brush.verticalGradient(
              0.45f to Color.Transparent,
              1.0f to ScrimBase.copy(alpha = 0.92f),
            )
          )
    )
    // Lock veil for locked characters.
    if (!unlocked) {
      Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
      Row(
        modifier =
          Modifier.align(Alignment.TopEnd)
            .padding(8.dp)
            .clip(RoundedCornerShape(50))
            .background(ScrimBase.copy(alpha = 0.8f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Icon(Icons.Rounded.Lock, contentDescription = "잠김", tint = Color.White, modifier = Modifier.size(13.dp))
        Spacer(modifier = Modifier.width(3.dp))
        Icon(Icons.Rounded.MonetizationOn, contentDescription = null, tint = CoinGold, modifier = Modifier.size(13.dp))
        Spacer(modifier = Modifier.width(2.dp))
        Text("${character.priceCoins}", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
      }
    } else if (selected) {
      Box(
        modifier =
          Modifier.align(Alignment.TopEnd)
            .padding(8.dp)
            .clip(RoundedCornerShape(50))
            .background(AccentPink)
            .padding(horizontal = 8.dp, vertical = 4.dp)
      ) {
        Text("사용 중", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
      }
    }
    Column(modifier = Modifier.align(Alignment.BottomStart).padding(12.dp)) {
      Text(
        character.name,
        color = Color.White,
        fontWeight = FontWeight.Bold,
        fontSize = 17.sp,
      )
      Text(
        character.tagline,
        color = Color.White.copy(alpha = 0.85f),
        fontSize = 11.sp,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CharacterDetail(
  character: Character,
  unlocked: Boolean,
  coins: Int,
  voices: List<VoiceOption>,
  selectedVoiceId: String,
  onSelectVoice: (String) -> Unit,
  onDismiss: () -> Unit,
  onChat: () -> Unit,
  onUnlockWithCoins: () -> Boolean,
  onSubscribe: () -> Unit,
) {
  var message by remember { mutableStateOf("") }

  Box(modifier = Modifier.fillMaxSize().background(ScrimBase)) {
    Image(
      painter = painterResource(character.imageRes),
      contentDescription = character.name,
      contentScale = ContentScale.Crop,
      alignment = Alignment.TopCenter,
      modifier = Modifier.fillMaxSize(),
    )
    Box(
      modifier =
        Modifier.fillMaxSize()
          .background(
            Brush.verticalGradient(
              0.0f to ScrimBase.copy(alpha = 0.15f),
              0.45f to ScrimBase.copy(alpha = 0.45f),
              0.72f to ScrimBase.copy(alpha = 0.92f),
              1.0f to ScrimBase,
            )
          )
    )

    Column(modifier = Modifier.fillMaxSize().systemBarsPadding().padding(20.dp)) {
      // Close.
      Box(
        modifier =
          Modifier.size(40.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.3f))
            .clickable { onDismiss() },
        contentAlignment = Alignment.Center,
      ) {
        Icon(Icons.Rounded.Close, contentDescription = "닫기", tint = Color.White, modifier = Modifier.size(20.dp))
      }

      Spacer(modifier = Modifier.weight(1f))

      Column(
        modifier = Modifier.verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        Text(character.name, color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 32.sp)
        Text(character.tagline, color = AccentPink, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        Text(character.intro, color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp, lineHeight = 20.sp)
        Text(character.personality, color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp, lineHeight = 19.sp)

        // Topic chips.
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
          character.topics.forEach { topic ->
            Box(
              modifier =
                Modifier.clip(RoundedCornerShape(50))
                  .background(Color.White.copy(alpha = 0.16f))
                  .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
              Text("# $topic", color = Color.White, fontSize = 12.sp)
            }
          }
        }

        // Voice (TTS engine + voice) selection for this character.
        Spacer(modifier = Modifier.height(2.dp))
        Text("보이스", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
        if (voices.isEmpty()) {
          Text(
            "음성을 준비하는 중이에요. 설정에서 음성 모델을 받으면 더 다양한 목소리를 고를 수 있어요.",
            color = Color.White.copy(alpha = 0.6f),
            fontSize = 12.sp,
            lineHeight = 17.sp,
          )
        } else {
          FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            voices.forEach { voice ->
              val selected = voice.id == selectedVoiceId
              Row(
                modifier =
                  Modifier.clip(RoundedCornerShape(50))
                    .background(if (selected) AccentPurple else Color.White.copy(alpha = 0.16f))
                    .clickable { onSelectVoice(voice.id) }
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
              ) {
                if (voice.isNeural || voice.isCloud) {
                  Icon(
                    Icons.Rounded.AutoAwesome,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(13.dp),
                  )
                  Spacer(modifier = Modifier.width(5.dp))
                }
                Text(voice.label, color = Color.White, fontSize = 12.sp)
              }
            }
          }
        }
      }

      Spacer(modifier = Modifier.height(16.dp))

      if (message.isNotEmpty()) {
        Text(message, color = CoinGold, fontSize = 13.sp, modifier = Modifier.padding(bottom = 8.dp))
      }

      // Call-to-action.
      if (unlocked) {
        GradientButton(text = "${character.name}와 대화하기", onClick = onChat)
      } else {
        GradientButton(
          text = "🪙 ${character.priceCoins} 코인으로 잠금 해제",
          onClick = {
            if (onUnlockWithCoins()) {
              onChat()
            } else {
              message = "코인이 부족해요. 구독하면 600 코인을 드려요!"
            }
          },
        )
        Spacer(modifier = Modifier.height(10.dp))
        Box(
          modifier =
            Modifier.fillMaxWidth()
              .clip(RoundedCornerShape(28.dp))
              .background(Color.White.copy(alpha = 0.14f))
              .clickable { onSubscribe() }
              .padding(vertical = 15.dp),
          contentAlignment = Alignment.Center,
        ) {
          Text("Pro 구독하고 모든 캐릭터 열기", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        }
      }
      Spacer(modifier = Modifier.height(8.dp))
    }
  }
}

@Composable
private fun GradientButton(text: String, onClick: () -> Unit) {
  Box(
    modifier =
      Modifier.fillMaxWidth()
        .clip(RoundedCornerShape(28.dp))
        .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
        .clickable { onClick() }
        .padding(vertical = 16.dp),
    contentAlignment = Alignment.Center,
  ) {
    Text(text, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
  }
}
