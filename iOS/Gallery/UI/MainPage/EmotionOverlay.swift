// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of ui/mainpage/EmotionOverlay.kt

import SwiftUI
import Foundation

// MARK: - EmotionOverlay

/// A non-interactive overlay that plays a brief "emotion" effect — emoji that float up,
/// pop and fade — whenever the assistant's reply contains emoji (instead of reading them
/// aloud). Mirrors the Android EmotionOverlay composable.
struct EmotionOverlay: View {
    let cue: EmotionCue?

    var body: some View {
        GeometryReader { geo in
            if let cue, !cue.emojis.isEmpty {
                EmotionBurst(emojis: cue.emojis, size: geo.size)
                    .id(cue.id)   // re-trigger when a new cue arrives
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - EmotionBurst

private struct ParticleConfig: Identifiable {
    let id: Int
    let emoji: String
    let startXFraction: Double
    let driftXFraction: Double
    let swayPx: Double
    let sizePt: Double
    let delayMs: Double
    let durationMs: Double
    let rotationDeg: Double
}

private struct EmotionBurst: View {
    let emojis: [String]
    let size: CGSize

    @State private var particles: [ParticleConfig] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(particles) { p in
                EmotionParticle(particle: p, size: size)
            }
        }
        .onAppear { buildParticles() }
    }

    private func buildParticles() {
        let count = 12
        particles = (0..<count).map { i in
            ParticleConfig(
                id: i,
                emoji: emojis[i % emojis.count],
                startXFraction: 0.18 + Double.random(in: 0..<0.64),
                driftXFraction: (Double.random(in: 0..<1) - 0.5) * 0.22,
                swayPx: (12 + Double.random(in: 0..<18)) * (Bool.random() ? 1 : -1),
                sizePt: 26 + Double.random(in: 0..<22),
                delayMs: Double(i * 60) + Double.random(in: 0..<140),
                durationMs: 1500 + Double.random(in: 0..<900),
                rotationDeg: (Double.random(in: 0..<1) - 0.5) * 36
            )
        }
    }
}

// MARK: - EmotionParticle

private struct EmotionParticle: View {
    let particle: ParticleConfig
    let size: CGSize

    @State private var progress: Double = 0

    var body: some View {
        let t = progress
        let alpha: Double = {
            if t < 0.12 { return t / 0.12 }
            if t > 0.7  { return max(0, (1 - t) / 0.3) }
            return 1
        }()
        let scale: Double = t < 0.25
            ? lerp(0.5, 1.15, t / 0.25)
            : lerp(1.15, 0.92, (t - 0.25) / 0.75)

        let startY = size.height * 0.72
        let rise   = size.height * 0.52
        let y = startY - rise * t
        let x = size.width * particle.startXFraction
              + size.width * particle.driftXFraction * t
              + sin(t * .pi * 2) * particle.swayPx

        Text(particle.emoji)
            .font(.system(size: particle.sizePt))
            .opacity(alpha)
            .scaleEffect(scale)
            .rotationEffect(.degrees(particle.rotationDeg * t))
            .position(x: x, y: y)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + particle.delayMs / 1000) {
                    withAnimation(.linear(duration: particle.durationMs / 1000)) {
                        progress = 1
                    }
                }
            }
    }
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(1, max(0, t))
}
