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

// Port of character/CharacterScreen.kt
//
// NOTE: VoiceAssistantViewModel and VoiceOption are defined in
// CustomTasks/VoiceAssistant/ (a separate agent's scope). This file declares
// the minimal VoiceOption type needed here; once VoiceAssistantViewModel.swift
// exists, replace the local typealias/struct with the real import.

import SwiftUI

// MARK: - Local palette (matches the Android file exactly)

private let scrimBase = Color(hex: 0x140A2B)
private let accentPurple = Color(hex: 0x7C4DFF)
private let accentPink = Color(hex: 0xE15BD0)
private let coinGold = Color(hex: 0xFFC93C)

// NOTE: `VoiceOption` is the real type defined in
// CustomTasks/VoiceAssistant/VoiceAssistantViewModel.swift and reused here.

// MARK: - CharacterScreen

/// The character-selection screen: a 2-column grid of companion cards.
/// Free characters can be selected directly; locked ones can be unlocked with
/// coins or by subscribing. Tapping a card opens a full-screen introduction.
///
/// Reached via `Route.characters` from the voice graph.
struct CharacterScreen: View {
    @ObservedObject var viewModel: CharacterViewModel
    /// Available TTS voices (passed down from VoiceAssistantViewModel).
    let availableVoices: [VoiceOption]
    let onStartChat: () -> Void
    let onOpenSubscription: () -> Void
    let navigateUp: () -> Void

    @State private var detail: Character? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.characters) { character in
                        CharacterCard(
                            character: character,
                            unlocked: viewModel.isUnlocked(character),
                            selected: viewModel.state.selectedId == character.id,
                            onClick: { detail = character }
                        )
                        .aspectRatio(0.74, contentMode: .fit)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("캐릭터 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: navigateUp) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if viewModel.state.isPro {
                        ProBadge()
                    }
                    CoinPill(coins: viewModel.state.coins)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(item: $detail) { character in
            CharacterDetail(
                character: character,
                unlocked: viewModel.isUnlocked(character),
                coins: viewModel.state.coins,
                voices: availableVoices,
                selectedVoiceId: viewModel.state.voiceByCharacter[character.id] ?? "",
                onSelectVoice: { voiceId in
                    viewModel.setVoiceForCharacter(character.id, voiceId: voiceId)
                },
                onDismiss: { detail = nil },
                onChat: {
                    viewModel.select(id: character.id)
                    viewModel.requestGreeting(characterId: character.id)
                    detail = nil
                    onStartChat()
                },
                onUnlockWithCoins: { viewModel.tryUnlockWithCoins(character) },
                onSubscribe: {
                    detail = nil
                    onOpenSubscription()
                }
            )
        }
    }
}

// MARK: - CoinPill

private struct CoinPill: View {
    let coins: Int
    @Environment(\.galleryColors) private var colors

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundColor(coinGold)
                .font(.system(size: 18))
            Text("\(coins)")
                .font(AppTypography.labelLarge)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.surfaceVariant)
        .clipShape(Capsule())
    }
}

// MARK: - ProBadge

private struct ProBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .foregroundColor(.white)
                .font(.system(size: 12))
            Text("PRO")
                .foregroundColor(.white)
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [accentPurple, accentPink],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
    }
}

// MARK: - CharacterCard

private struct CharacterCard: View {
    let character: Character
    let unlocked: Bool
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    // Portrait image
                    Image(character.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Bottom scrim
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.45),
                            .init(color: scrimBase.opacity(0.92), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Lock veil for locked characters
                    if !unlocked {
                        Color.black.opacity(0.35)
                    }

                    // Name + tagline
                    VStack(alignment: .leading, spacing: 2) {
                        Text(character.name)
                            .foregroundColor(.white)
                            .font(.system(size: 17, weight: .bold))
                        Text(character.tagline)
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .padding(12)

                    // Top-right badge
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                        if !unlocked {
                            HStack(spacing: 2) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 10))
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(coinGold)
                                    .font(.system(size: 10))
                                Text("\(character.priceCoins)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(scrimBase.opacity(0.8))
                            .clipShape(Capsule())
                            .padding(8)
                        } else if selected {
                            Text("사용 중")
                                .foregroundColor(.white)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(accentPink)
                                .clipShape(Capsule())
                                .padding(8)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selected ? accentPink : Color.clear, lineWidth: 2.5)
                )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CharacterDetail

private struct CharacterDetail: View {
    let character: Character
    let unlocked: Bool
    let coins: Int
    let voices: [VoiceOption]
    let selectedVoiceId: String
    let onSelectVoice: (String) -> Void
    let onDismiss: () -> Void
    let onChat: () -> Void
    let onUnlockWithCoins: () -> Bool
    let onSubscribe: () -> Void

    @State private var message: String = ""

    var body: some View {
        ZStack {
            scrimBase.ignoresSafeArea()

            // Full-bleed portrait
            Image(character.imageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Multi-stop scrim
            LinearGradient(
                stops: [
                    .init(color: scrimBase.opacity(0.15), location: 0.0),
                    .init(color: scrimBase.opacity(0.45), location: 0.45),
                    .init(color: scrimBase.opacity(0.92), location: 0.72),
                    .init(color: scrimBase, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .padding(.top, 8)

                Spacer()

                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(character.name)
                            .foregroundColor(.white)
                            .font(.system(size: 32, weight: .black))
                        Text(character.tagline)
                            .foregroundColor(accentPink)
                            .font(.system(size: 15, weight: .semibold))
                        Text(character.intro)
                            .foregroundColor(.white.opacity(0.9))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                        Text(character.personality)
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 13))
                            .lineSpacing(3)

                        // Topic chips
                        FlowLayout(spacing: 8) {
                            ForEach(character.topics, id: \.self) { topic in
                                Text("# \(topic)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }

                        // Voice selection
                        Spacer().frame(height: 2)
                        Text("보이스")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .semibold))

                        if voices.isEmpty {
                            Text("음성을 준비하는 중이에요. 설정에서 음성 모델을 받으면 더 다양한 목소리를 고를 수 있어요.")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 12))
                                .lineSpacing(4)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(voices) { voice in
                                    let isSelected = voice.id == selectedVoiceId
                                    Button(action: { onSelectVoice(voice.id) }) {
                                        HStack(spacing: 5) {
                                            if voice.isNeural || voice.isCloud {
                                                Image(systemName: "sparkles")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 11))
                                            }
                                            Text(voice.label)
                                                .foregroundColor(.white)
                                                .font(.system(size: 12))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? accentPurple : Color.white.opacity(0.16))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Spacer().frame(height: 16)

                // Feedback message (e.g. "코인이 부족해요…")
                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(coinGold)
                        .font(.system(size: 13))
                        .padding(.bottom, 8)
                }

                // Call-to-action
                if unlocked {
                    GradientButton(text: "\(character.name)와 대화하기", action: onChat)
                } else {
                    GradientButton(
                        text: "🪙 \(character.priceCoins) 코인으로 잠금 해제",
                        action: {
                            if onUnlockWithCoins() {
                                onChat()
                            } else {
                                message = "코인이 부족해요. 구독하면 600 코인을 드려요!"
                            }
                        }
                    )
                    Spacer().frame(height: 10)
                    Button(action: onSubscribe) {
                        Text("Pro 구독하고 모든 캐릭터 열기")
                            .foregroundColor(.white)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                    }
                    .buttonStyle(.plain)
                }

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - GradientButton

private struct GradientButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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
    }
}

// MARK: - FlowLayout (Compose FlowRow equivalent)

/// A simple horizontal-wrapping layout (polyfill for iOS < 16 `Layout`).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        _ = maxWidth // suppress warning
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let repo = CharacterRepository()
    let vm = CharacterViewModel(repository: repo)
    return NavigationStack {
        CharacterScreen(
            viewModel: vm,
            availableVoices: [],
            onStartChat: {},
            onOpenSubscription: {},
            navigateUp: {}
        )
    }
    .environment(\.galleryColors, lightScheme)
    .environment(\.customColors, lightCustomColors)
}
#endif
