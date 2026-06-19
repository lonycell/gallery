/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/GlitteringShapesLoader.kt
//
// NOTE: Android loaded vector drawables (circle, double_circle, pantegon, four_circle)
// as Image resources. These are mapped to SF Symbols approximations here; replace with
// matching asset-catalog images if the exact shapes are added to the iOS asset catalog.

import SwiftUI

// MARK: - Data

private let SHAPE_SYSTEM_NAMES = ["circle.fill", "circle.circle.fill", "pentagon.fill", "4.circle.fill"]
private let PARTICLE_ANIMATION_DURATION: Double = 0.3  // seconds
private let PARTICLE_ALIVE_S: Double = 0.6
private let PARTICLE_BASE_SIZE: CGFloat = 6
private let BATCH_SIZE = 5
private let BATCH_INTERVAL_S: Double = 0.3

private struct GlitterShape: Identifiable {
  let id: Int64
  let systemName: String
  let relativeX: Float
  let relativeY: Float
  let size: CGFloat
  let color: Color
  let addedAt: Date
}

private var globalId: Int64 = 0

// MARK: - GlitteringShapesLoader

/// Animated particle loader showing randomly placed and coloured shapes.
/// Mirrors `GlitteringShapesLoader` composable.
struct GlitteringShapesLoader: View {
  @State private var shapes: [GlitterShape] = []
  @Environment(\.customColors) private var customColors

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .topLeading) {
        ForEach(shapes) { shape in
          ParticleView(shape: shape, containerSize: geo.size)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task {
      while !_Concurrency.Task.isCancelled {
        let iconColors = customColors.taskIconColors
        var newShapes: [GlitterShape] = []
        for _ in 0..<BATCH_SIZE {
          globalId += 1
          newShapes.append(GlitterShape(
            id: globalId,
            systemName: SHAPE_SYSTEM_NAMES[Int.random(in: 0..<SHAPE_SYSTEM_NAMES.count)],
            relativeX: Float.random(in: 0...1),
            relativeY: Float.random(in: 0...1),
            size: PARTICLE_BASE_SIZE + CGFloat(Int.random(in: -2...2)),
            color: iconColors[Int.random(in: 0..<max(1, iconColors.count))],
            addedAt: Date()
          ))
        }
        let now = Date()
        let alive = shapes.filter { now.timeIntervalSince($0.addedAt) < PARTICLE_ANIMATION_DURATION * 2 + PARTICLE_ALIVE_S + 0.1 }
        shapes = newShapes + alive
        try? await _Concurrency.Task.sleep(nanoseconds: UInt64(BATCH_INTERVAL_S * 1_000_000_000))
      }
    }
  }
}

// MARK: - ParticleView

private struct ParticleView: View {
  let shape: GlitterShape
  let containerSize: CGSize

  @State private var progress: Double = 0

  var body: some View {
    Image(systemName: shape.systemName)
      .resizable()
      .frame(width: shape.size, height: shape.size)
      .foregroundStyle(shape.color.opacity(0.95))
      .scaleEffect(progress)
      .position(
        x: containerSize.width * CGFloat(shape.relativeX),
        y: containerSize.height * CGFloat(shape.relativeY)
      )
      .onAppear {
        let delay = Double.random(in: 0...0.05)
        // Enter
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
          withAnimation(.linear(duration: PARTICLE_ANIMATION_DURATION)) { progress = 1 }
        }
        // Exit
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + PARTICLE_ALIVE_S) {
          withAnimation(.linear(duration: PARTICLE_ANIMATION_DURATION)) { progress = 0 }
        }
      }
  }
}

