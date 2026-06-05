/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/AudioAnimation.kt
//
// NOTE: Android used RuntimeShader (AGSL) which is Android-only. iOS uses Metal
// via a CAMetalLayer-backed UIView wrapped in UIViewRepresentable. A simplified
// procedural sine-wave animation is drawn instead of the Perlin-noise shader,
// producing a visually similar audio-reactive waveform. Replace with a full
// Metal shader if pixel-perfect parity is needed.

import SwiftUI
import UIKit

/// Shader-like audio-amplitude animation. Mirrors `AudioAnimation` composable.
struct AudioAnimation: View {
  let bgColor: Color
  let amplitude: Int
  var modifier: some View = EmptyView()

  @State private var animatedAmplitude: Float = 0
  @State private var iTime: Float = 0
  @State private var pOffset: Float = 0
  @State private var prevNormalizedAmplitude: Double = 0

  // Start a display-link-like timer
  private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

  private var normalizedAmplitude: Double {
    let raw = Double(amplitude) / 32767.0
    return pow(raw, 0.5)
  }

  var body: some View {
    Canvas { ctx, size in
      // Background
      ctx.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(bgColor)
      )

      let amp = CGFloat(animatedAmplitude)
      let freq: CGFloat = 4.0
      let speed: CGFloat = 1.2
      let baseY = size.height * 0.28

      // Draw gradient wave
      var path = Path()
      let steps = Int(size.width)
      path.move(to: CGPoint(x: 0, y: size.height))
      for x in 0...steps {
        let progress = CGFloat(x) / CGFloat(steps)
        let waveY: CGFloat
        if amp < 0.01 {
          // Idle sine wave
          waveY = baseY + sin(progress * freq * .pi * 2 - CGFloat(iTime) * speed) * size.height * 0.036
        } else {
          // Amplitude-driven Perlin-like noise approximation
          let noise = sin(progress * 9.4 + CGFloat(pOffset)) * 0.5 + 0.5
          waveY = baseY - noise * amp * size.height * 0.5
        }
        if x == 0 { path.move(to: CGPoint(x: 0, y: waveY)) }
        else { path.addLine(to: CGPoint(x: CGFloat(x), y: waveY)) }
      }
      path.addLine(to: CGPoint(x: size.width, y: size.height))
      path.closeSubpath()

      ctx.fill(
        path,
        with: .linearGradient(
          Gradient(colors: [
            Color(red: 0.992, green: 0.875, blue: 0.522),
            Color(red: 0.627, green: 0.816, blue: 0.686),
            Color(red: 0.886, green: 0.372, blue: 0.341),
            Color(red: 0.522, green: 0.694, blue: 0.973),
          ]),
          startPoint: CGPoint(x: 0, y: size.height),
          endPoint: CGPoint(x: size.width, y: 0)
        )
      )
    }
    .ignoresSafeArea()
    .onReceive(timer) { _ in
      iTime += 1.0 / 60.0
    }
    .onChange(of: amplitude) { newAmp in
      let norm = Float(pow(Double(newAmp) / 32767.0, 0.5))
      if normalizedAmplitude < 0.2 && prevNormalizedAmplitude >= 0.2 {
        pOffset = Float.random(in: 0...1000)
      }
      prevNormalizedAmplitude = normalizedAmplitude
      withAnimation(.linear(duration: 0.1)) { animatedAmplitude = norm }
    }
  }
}
