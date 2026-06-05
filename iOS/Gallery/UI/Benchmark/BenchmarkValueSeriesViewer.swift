// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/benchmark/BenchmarkValueSeriesViewer.kt

import SwiftUI

/// Bottom sheet showing a sparkline and aggregate stats for a `ValueSeries`.
/// Mirrors `BenchmarkValueSeriesViewer`.
struct BenchmarkValueSeriesViewer: View {
  let title: String
  let valueSeries: ValueSeries
  let onDismiss: () -> Void

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  @State private var tappedValue: Double? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(AppTypography.titleMedium)
        .foregroundStyle(colors.onSurface)

      let values = valueSeries.value

      if !values.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          // Tap label
          Text(tappedValue == nil
               ? Str.tapToSeeValue
               : String(format: "Value: %.2f", tappedValue!))
            .font(AppTypography.labelMedium)
            .foregroundStyle(colors.onSurfaceVariant)

          // Sparkline canvas
          SparklineView(
            values: values,
            min: valueSeries.min,
            max: valueSeries.max,
            lineColor: colors.outline,
            dotBgColor: colors.surface,
            dotBorderColor: colors.outline,
            tappedLineColor: customColors.linkColor,
            tappedValue: $tappedValue
          )
          .frame(maxWidth: .infinity)
          .frame(height: 80)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(colors.surfaceContainer)
          )
        }

        // Stats row
        HStack {
          StatCell(key: "avg", value: valueSeries.avg)
          Spacer()
          StatCell(key: "median", value: valueSeries.medium)
          Spacer()
          StatCell(key: "min", value: valueSeries.min)
          Spacer()
          StatCell(key: "max", value: valueSeries.max)
        }
      }

      Spacer().frame(height: 16)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

// MARK: - Sparkline

private struct SparklineView: View {
  let values: [Double]
  let min: Double
  let max: Double
  let lineColor: Color
  let dotBgColor: Color
  let dotBorderColor: Color
  let tappedLineColor: Color
  @Binding var tappedValue: Double?

  private let verticalPaddingFactor = 0.2
  private var effectiveMin: Double { min - (max - min) * verticalPaddingFactor }
  private var effectiveMax: Double { max + (max - min) * verticalPaddingFactor }
  private var scaledYRange: Double { effectiveMax - effectiveMin }

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let hPad: CGFloat = 12
      let usableW = w - hPad * 2
      let xStep = values.count > 1 ? usableW / CGFloat(values.count - 1) : 0

      let points: [CGPoint] = values.enumerated().map { (i, v) in
        let x = CGFloat(i) * xStep + hPad
        let y = h - CGFloat((v - effectiveMin) / scaledYRange) * h
        return CGPoint(x: x, y: y)
      }

      ZStack {
        // Lines
        Path { path in
          for (i, pt) in points.enumerated() {
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
          }
        }
        .stroke(lineColor, lineWidth: 2)

        // Dots
        ForEach(points.indices, id: \.self) { i in
          Circle()
            .fill(dotBgColor)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(dotBorderColor, lineWidth: 2))
            .position(points[i])
        }

        // Tapped dashed line
        if let tv = tappedValue {
          let ty = h - CGFloat((tv - effectiveMin) / scaledYRange) * h
          Path { path in
            path.move(to: CGPoint(x: 0, y: ty))
            path.addLine(to: CGPoint(x: w, y: ty))
          }
          .stroke(
            style: StrokeStyle(lineWidth: 1, dash: [10, 10])
          )
          .foregroundStyle(tappedLineColor)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let ty = value.location.y
            let tv = effectiveMin + (1 - Double(ty / h)) * scaledYRange
            tappedValue = tv
          }
      )
    }
  }
}

// MARK: - Stat cell

private struct StatCell: View {
  let key: String
  let value: Double
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(String(format: "%.2f", value))
        .font(AppTypography.labelMedium)
        .foregroundStyle(colors.onSurfaceVariant)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Text(key)
        .font(AppTypography.labelSmall)
        .foregroundStyle(colors.onSurfaceVariant.opacity(0.7))
    }
  }
}
