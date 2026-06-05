/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBubbleShape.kt

import SwiftUI

/// Chat-bubble shape with configurable hard corner.
///
/// `hardCornerAtLeftOrRight = false` → hard corner at top-right (user bubble).
/// `hardCornerAtLeftOrRight = true`  → hard corner at top-left  (agent bubble).
struct MessageBubbleShape: Shape {
  var radius: CGFloat
  /// When true the hard (unrounded) corner is on the top-left; otherwise top-right.
  var hardCornerAtLeftOrRight: Bool = false

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let r = radius

    // Top-left corner
    let topLeftRadius: CGFloat = hardCornerAtLeftOrRight ? 0 : r
    // Top-right corner
    let topRightRadius: CGFloat = hardCornerAtLeftOrRight ? r : 0
    let bottomLeftRadius: CGFloat = r
    let bottomRightRadius: CGFloat = r

    path.move(to: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY))
    if topRightRadius > 0 {
      path.addArc(center: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY + topRightRadius),
                  radius: topRightRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
    path.addArc(center: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY - bottomRightRadius),
                radius: bottomRightRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    path.addLine(to: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY))
    path.addArc(center: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY - bottomLeftRadius),
                radius: bottomLeftRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeftRadius))
    if topLeftRadius > 0 {
      path.addArc(center: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY + topLeftRadius),
                  radius: topLeftRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
    }
    path.closeSubpath()
    return path
  }
}
