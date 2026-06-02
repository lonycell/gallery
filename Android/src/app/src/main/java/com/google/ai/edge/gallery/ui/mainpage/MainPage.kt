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

import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.KeyboardDoubleArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.ai.edge.gallery.R

// Paywall palette, tuned to match the reference mock-up (deep purple + violet/pink accents).
private val ScrimBase = Color(0xFF140A2B)
private val AccentPurple = Color(0xFF7C4DFF)
private val AccentPink = Color(0xFFE15BD0)
private val FeatureBullet = Color(0xFFFFB23E)

/** A single selectable subscription plan shown in the pricing row. */
private data class PlanOption(
  @StringRes val nameRes: Int,
  @StringRes val priceRes: Int,
  @StringRes val badgeRes: Int?,
  /** Whether the badge uses the highlighted (gradient) style. */
  val badgeHighlighted: Boolean,
)

/**
 * The app's main landing / paywall screen, shown first as the start destination.
 *
 * The layout mirrors a "Pro" subscription paywall: a full-bleed persona hero image with a purple
 * scrim, the app brand with a Pro badge, a value proposition title, a feature list, three
 * selectable pricing plans and a purchase call-to-action.
 *
 * There is no real billing integration in this project, so both the close button and the purchase
 * button simply continue into the main app via [onGetStarted], reusing the existing navigation
 * contract. Plan selection is local UI state that drives the price shown on the CTA.
 *
 * Registered in the nav graph under the `mainpage` route. See
 * [com.google.ai.edge.gallery.ui.navigation.GalleryNavHost].
 */
@Composable
fun MainPage(onGetStarted: () -> Unit, modifier: Modifier = Modifier) {
  val plans =
    listOf(
      PlanOption(R.string.paywall_plan_weekly, R.string.paywall_price_weekly, null, false),
      PlanOption(
        R.string.paywall_plan_yearly,
        R.string.paywall_price_yearly,
        R.string.paywall_badge_best_value,
        badgeHighlighted = true,
      ),
      PlanOption(
        R.string.paywall_plan_monthly,
        R.string.paywall_price_monthly,
        R.string.paywall_badge_most_popular,
        badgeHighlighted = false,
      ),
    )
  // Default to the "Yearly / BEST VALUE" plan, matching the reference design.
  var selectedIndex by remember { mutableIntStateOf(1) }

  val featureRes =
    listOf(
      R.string.paywall_feature_1,
      R.string.paywall_feature_2,
      R.string.paywall_feature_3,
      R.string.paywall_feature_4,
      R.string.paywall_feature_5,
      R.string.paywall_feature_6,
      R.string.paywall_feature_7,
    )

  Box(modifier = modifier.fillMaxSize().background(ScrimBase)) {
    // Full-bleed persona hero image.
    Image(
      painter = painterResource(R.drawable.persona_hero),
      contentDescription = null,
      contentScale = ContentScale.Crop,
      alignment = Alignment.TopCenter,
      modifier = Modifier.fillMaxSize(),
    )
    // Purple scrim so the content stays readable over the photo.
    Box(
      modifier =
        Modifier.fillMaxSize()
          .background(
            Brush.verticalGradient(
              0.0f to ScrimBase.copy(alpha = 0.20f),
              0.42f to ScrimBase.copy(alpha = 0.60f),
              0.70f to ScrimBase.copy(alpha = 0.95f),
              1.0f to ScrimBase,
            )
          )
    )

    Column(modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 20.dp)) {
      // Close button.
      Box(
        modifier =
          Modifier.padding(top = 8.dp)
            .size(36.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.25f))
            .clickable { onGetStarted() },
        contentAlignment = Alignment.Center,
      ) {
        Icon(
          Icons.Rounded.Close,
          contentDescription = stringResource(R.string.paywall_close),
          tint = Color.White,
          modifier = Modifier.size(20.dp),
        )
      }

      // Brand + Pro badge.
      Row(
        modifier = Modifier.padding(top = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
          text = stringResource(R.string.app_name),
          color = Color.White,
          fontWeight = FontWeight.Bold,
          fontSize = 26.sp,
        )
        Spacer(modifier = Modifier.size(8.dp))
        Box(
          modifier =
            Modifier.clip(RoundedCornerShape(8.dp))
              .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
              .padding(horizontal = 8.dp, vertical = 2.dp)
        ) {
          Text(
            text = stringResource(R.string.paywall_pro_badge),
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
          )
        }
      }

      // Reveal the hero face before the value proposition.
      Spacer(modifier = Modifier.weight(0.45f))

      // Value proposition title.
      Text(
        text = stringResource(R.string.paywall_title),
        color = Color.White,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 30.sp,
        lineHeight = 36.sp,
      )

      Spacer(modifier = Modifier.size(16.dp))

      // Feature list.
      Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (res in featureRes) {
          FeatureRow(text = stringResource(res))
        }
      }

      // Push the pricing + CTA to the bottom.
      Spacer(modifier = Modifier.weight(1f))

      // Pricing plans.
      Row(
        modifier = Modifier.fillMaxWidth().padding(top = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        plans.forEachIndexed { index, plan ->
          PlanCard(
            plan = plan,
            selected = index == selectedIndex,
            onClick = { selectedIndex = index },
            modifier = Modifier.weight(1f),
          )
        }
      }

      Spacer(modifier = Modifier.size(16.dp))

      // Purchase call-to-action. Shows the price of the selected plan.
      val price = stringResource(plans[selectedIndex].priceRes)
      Box(
        modifier =
          Modifier.fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
            .clickable { onGetStarted() },
        contentAlignment = Alignment.Center,
      ) {
        Text(
          text = stringResource(R.string.paywall_cta, price),
          color = Color.White,
          fontWeight = FontWeight.Bold,
          fontSize = 17.sp,
        )
      }

      Spacer(modifier = Modifier.size(12.dp))
    }
  }
}

@Composable
private fun FeatureRow(text: String, modifier: Modifier = Modifier) {
  Row(modifier = modifier, verticalAlignment = Alignment.Top) {
    Icon(
      Icons.Rounded.KeyboardDoubleArrowRight,
      contentDescription = null,
      tint = FeatureBullet,
      modifier = Modifier.size(20.dp),
    )
    Spacer(modifier = Modifier.size(10.dp))
    Text(
      text = text,
      color = Color.White,
      fontSize = 14.sp,
      lineHeight = 19.sp,
      style = MaterialTheme.typography.bodyMedium,
    )
  }
}

@Composable
private fun PlanCard(
  plan: PlanOption,
  selected: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
    // Badge sits above the card. Reserve the height even when absent so cards stay aligned.
    Box(modifier = Modifier.height(22.dp), contentAlignment = Alignment.Center) {
      if (plan.badgeRes != null) {
        val badgeModifier =
          if (plan.badgeHighlighted) {
            Modifier.background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
          } else {
            Modifier.background(Color.White.copy(alpha = 0.20f))
          }
        Box(
          modifier =
            Modifier.clip(RoundedCornerShape(8.dp)).then(badgeModifier).padding(
              horizontal = 8.dp,
              vertical = 3.dp,
            )
        ) {
          Text(
            text = stringResource(plan.badgeRes),
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 9.sp,
            maxLines = 1,
          )
        }
      }
    }

    Spacer(modifier = Modifier.size(6.dp))

    val cardModifier =
      if (selected) {
        Modifier.background(AccentPurple.copy(alpha = 0.92f))
          .border(2.dp, Color.White.copy(alpha = 0.7f), RoundedCornerShape(18.dp))
      } else {
        Modifier.background(Color.White.copy(alpha = 0.12f))
      }
    Box(
      modifier =
        Modifier.fillMaxWidth()
          .height(96.dp)
          .clip(RoundedCornerShape(18.dp))
          .then(cardModifier)
          .clickable { onClick() },
      contentAlignment = Alignment.Center,
    ) {
      Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
      ) {
        Text(
          text = stringResource(plan.nameRes),
          color = Color.White,
          fontWeight = FontWeight.Bold,
          fontSize = 15.sp,
          maxLines = 1,
        )
        Text(
          text = stringResource(plan.priceRes),
          color = Color.White.copy(alpha = 0.9f),
          fontSize = 13.sp,
          maxLines = 1,
        )
      }
    }
  }
}
