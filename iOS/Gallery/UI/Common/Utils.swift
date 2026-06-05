/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/Utils.kt

import SwiftUI
import Foundation

// MARK: - Layout constants

let SMALL_BUTTON_CONTENT_PADDING = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

// MARK: - Number formatting

extension Int64 {
  /// Format to a human-readable size string. Mirrors `Long.humanReadableSize()`.
  func humanReadableSize(si: Bool = true, extraDecimalForGbAndAbove: Bool = false) -> String {
    let bytes = self
    let unit: Int64 = si ? 1000 : 1024
    if bytes < unit { return "\(bytes) B" }
    let exp = Int(log(Double(bytes)) / log(Double(unit)))
    let siPre = "kMGTPE"
    let biPre = "KMGTPE"
    let pre = String((si ? siPre : biPre)[siPre.index(siPre.startIndex, offsetBy: exp - 1)])
      + (si ? "" : "i")
    let value = Double(bytes) / pow(Double(unit), Double(exp))
    let format: String
    if extraDecimalForGbAndAbove && exp >= 3 {
      format = "%.2f \(pre)B"
    } else {
      format = "%.1f \(pre)B"
    }
    return String(format: format, value)
  }
}

extension Float {
  /// Format a millisecond duration to a human-readable string. Mirrors `Float.humanReadableDuration()`.
  func humanReadableDuration() -> String {
    let milliseconds = self
    if milliseconds < 1000 { return "\(milliseconds) ms" }
    let seconds = milliseconds / 1000
    if seconds < 60 { return String(format: "%.1f s", seconds) }
    let minutes = seconds / 60
    if minutes < 60 { return String(format: "%.1f min", minutes) }
    let hours = minutes / 60
    return String(format: "%.1f h", hours)
  }
}

extension Int64 {
  /// Format milliseconds to "Xh Xmin Xsec". Mirrors `Long.formatToHourMinSecond()`.
  func formatToHourMinSecond() -> String {
    let ms = self
    if ms < 0 { return "-" }
    let seconds = ms / 1000
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remaining = seconds % 60
    var parts: [String] = []
    if hours > 0 { parts.append("\(hours) h") }
    if minutes > 0 { parts.append("\(minutes) min") }
    if remaining > 0 || (hours == 0 && minutes == 0) { parts.append("\(remaining) sec") }
    return parts.joined(separator: " ")
  }
}

/// A set of visually distinctive colours for chart lines / debug use. Mirrors `getDistinctiveColor()`.
func getDistinctiveColor(index: Int) -> Color {
  let colors: [Color] = [
    Color(red: 0x3c/255, green: 0xb4/255, blue: 0x4b/255),
    Color(red: 0xff/255, green: 0xe1/255, blue: 0x19/255),
    Color(red: 0x43/255, green: 0x63/255, blue: 0xd8/255),
    Color(red: 0xf5/255, green: 0x82/255, blue: 0x31/255),
    Color(red: 0x91/255, green: 0x1e/255, blue: 0xb4/255),
    Color(red: 0x46/255, green: 0xf0/255, blue: 0xf0/255),
    Color(red: 0xf0/255, green: 0x32/255, blue: 0xe6/255),
    Color(red: 0xbc/255, green: 0xf6/255, blue: 0x0c/255),
    Color(red: 0xfa/255, green: 0xbe/255, blue: 0xbe/255),
    Color(red: 0x00/255, green: 0x80/255, blue: 0x80/255),
  ]
  return colors[index % colors.count]
}

// MARK: - Animated text composables

/// Animates text revealing from left to right using a gradient mask.
/// Mirrors `SwipingText` composable.
struct SwipingText: View {
  let text: String
  let style: Font
  let color: Color
  var animationDelay: Double = 0
  var animationDurationMs: Int = 300

  @State private var progress: CGFloat = 0

  var body: some View {
    Text(text)
      .font(style)
      .foregroundStyle(
        LinearGradient(
          stops: [
            .init(color: color, location: (1 + 1.0) * progress - 1.0),
            .init(color: .clear, location: (1 + 1.0) * progress),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .opacity(Double(progress))
      .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay / 1000) {
          withAnimation(.linear(duration: Double(animationDurationMs) / 1000)) {
            progress = 1
          }
        }
      }
  }
}

/// Reveals text from left to right using a gradient mask, with optional AnnotatedString support.
/// Mirrors `RevealingText` composable.
struct RevealingText: View {
  let text: String
  var style: Font = AppTypography.bodyMedium
  var animationProgress: CGFloat? = nil
  var animationDelay: Double = 0
  var animationDurationMs: Int = 300
  var textAlign: TextAlignment = .leading

  @State private var internalProgress: CGFloat = 0

  private var currentProgress: CGFloat {
    animationProgress ?? internalProgress
  }

  var body: some View {
    Text(text)
      .font(style)
      .multilineTextAlignment(textAlign)
      .padding(.horizontal, 16)
      .mask(
        LinearGradient(
          stops: [
            .init(color: .white, location: (1 + 0.5) * currentProgress - 0.5),
            .init(color: .clear, location: (1 + 0.5) * currentProgress),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .onAppear {
        guard animationProgress == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay / 1000) {
          withAnimation(.easeInOut(duration: Double(animationDurationMs) / 1000)) {
            internalProgress = 1
          }
        }
      }
  }
}

// MARK: - Memory check

/// Returns true if the device has less RAM than the model requires.
/// Mirrors `isMemoryLow()`.
func isMemoryLow(model: Model) -> Bool {
  guard let minGb = model.minDeviceMemoryInGb else { return false }
  var info = vm_statistics64()
  var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
    }
  }
  if result != KERN_SUCCESS { return false }
  let pageSize = Int64(vm_kernel_page_size)
  let totalPages = Int64(ProcessInfo.processInfo.physicalMemory) / pageSize
  let totalGb = Double(totalPages) * Double(pageSize) / 1_073_741_824
  return totalGb < Double(minGb)
}

/// Ensures valid filesystem name. Mirrors `ensureValidFileName()`.
func ensureValidFileName(_ fileName: String) -> String {
  let invalid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").inverted
  return fileName.components(separatedBy: invalid).joined(separator: "_")
}
