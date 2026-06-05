// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of ui/subscription/SubscriptPage.kt
//
// NOTE: StoreKit / real billing is not integrated. The purchase button calls
// `onPurchase()` (a closure injected by the caller) and then dismisses. Wire a
// real StoreKit 2 product fetch + purchase flow inside `onPurchase` when billing
// is ready. The plan prices below come from Str.paywall_price_*.

import SwiftUI

// MARK: - Paywall palette

private let scrimBase    = Color(hex: 0x140A2B)
private let accentPurple = Color(hex: 0x7C4DFF)
private let accentPink   = Color(hex: 0xE15BD0)
private let featureBullet = Color(hex: 0xFFB23E)

// MARK: - Plan model

private struct PlanOption: Identifiable {
    let id = UUID()
    let name: String
    let price: String
    let badge: String?
    let badgeHighlighted: Bool
}

// MARK: - SubscriptPage

/// The "Pro" subscription paywall screen.
///
/// Full-bleed `persona_hero` image with a purple scrim, app brand + Pro badge,
/// value proposition title, feature list, three selectable pricing plans, and a
/// purchase CTA.
///
/// Registered in the nav graph under `Route.subscription`. Accepts `onClose` and
/// `onPurchase` closures so the caller (NavHost / CharacterScreen) drives navigation.
struct SubscriptPage: View {
    let onClose: () -> Void
    var onPurchase: () -> Void = {}

    @State private var selectedIndex: Int = 1   // Default: Yearly / BEST VALUE

    private var plans: [PlanOption] {
        [
            PlanOption(name: Str.paywallPlanWeekly,
                       price: Str.paywallPriceWeekly,
                       badge: nil,
                       badgeHighlighted: false),
            PlanOption(name: Str.paywallPlanYearly,
                       price: Str.paywallPriceYearly,
                       badge: Str.paywallBadgeBestValue,
                       badgeHighlighted: true),
            PlanOption(name: Str.paywallPlanMonthly,
                       price: Str.paywallPriceMonthly,
                       badge: Str.paywallBadgeMostPopular,
                       badgeHighlighted: false),
        ]
    }

    private let features: [String] = [
        Str.paywallFeature1,
        Str.paywallFeature2,
        Str.paywallFeature3,
        Str.paywallFeature4,
        Str.paywallFeature5,
        Str.paywallFeature6,
        Str.paywallFeature7,
    ]

    var body: some View {
        ZStack {
            scrimBase.ignoresSafeArea()

            // Full-bleed hero image
            Image("persona_hero")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Multi-stop scrim
            LinearGradient(
                stops: [
                    .init(color: scrimBase.opacity(0.20), location: 0.0),
                    .init(color: scrimBase.opacity(0.60), location: 0.42),
                    .init(color: scrimBase.opacity(0.95), location: 0.70),
                    .init(color: scrimBase,               location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content column
            VStack(alignment: .leading, spacing: 0) {
                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Circle())
                }
                .padding(.top, 8)

                // Brand + Pro badge
                HStack(spacing: 8) {
                    Text(Str.appName)
                        .foregroundColor(.white)
                        .font(.system(size: 26, weight: .bold))
                    Text(Str.paywallProBadge)
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: [accentPurple, accentPink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.top, 12)

                // Reveal hero face
                Spacer(minLength: 0).frame(maxHeight: 180)

                // Value proposition
                Text(Str.paywallTitle)
                    .foregroundColor(.white)
                    .font(.system(size: 30, weight: .black))
                    .lineSpacing(5)

                Spacer().frame(height: 16)

                // Feature list
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(features, id: \.self) { feature in
                        FeatureRow(text: feature)
                    }
                }

                Spacer(minLength: 16)

                // Pricing plans
                HStack(spacing: 10) {
                    ForEach(Array(plans.enumerated()), id: \.offset) { index, plan in
                        PlanCard(
                            plan: plan,
                            selected: index == selectedIndex,
                            onClick: { selectedIndex = index }
                        )
                    }
                }
                .padding(.top, 20)

                Spacer().frame(height: 16)

                // CTA button
                let price = plans[selectedIndex].price
                Button(action: {
                    // NOTE: Wire StoreKit 2 product.purchase() here and call
                    // onPurchase() on success. For now both close the screen.
                    onPurchase()
                    onClose()
                }) {
                    Text(String(format: Str.paywallCta.replacingOccurrences(of: "%1$s", with: "%@"), price))
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [accentPurple, accentPink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chevron.right.2")
                .foregroundColor(featureBullet)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(text)
                .foregroundColor(.white)
                .font(AppTypography.bodyMedium)
                .lineSpacing(4)
        }
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let plan: PlanOption
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Badge row — reserve height even when absent
            ZStack {
                Color.clear.frame(height: 22)
                if let badge = plan.badge {
                    Text(badge)
                        .foregroundColor(.white)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            plan.badgeHighlighted
                            ? AnyShapeStyle(LinearGradient(
                                colors: [accentPurple, accentPink],
                                startPoint: .leading,
                                endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.20))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer().frame(height: 6)

            Button(action: onClick) {
                VStack(spacing: 4) {
                    Text(plan.name)
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text(plan.price)
                        .foregroundColor(.white.opacity(0.9))
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .background(
                    selected
                    ? AnyShapeStyle(accentPurple.opacity(0.92))
                    : AnyShapeStyle(Color.white.opacity(0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(selected ? Color.white.opacity(0.7) : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SubscriptPage(onClose: {})
}
#endif
