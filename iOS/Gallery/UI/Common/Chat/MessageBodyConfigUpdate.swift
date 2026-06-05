/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyConfigUpdate.kt

import SwiftUI

struct MessageBodyConfigUpdate: View {
  let message: ChatMessageConfigValuesChange

  @Environment(\.galleryColors) private var colors

  private struct RowData {
    let label: String
    let oldDisplay: String
    let newDisplay: String
    let changed: Bool
  }

  private var rows: [RowData] {
    let old = message.oldValues
    let new = message.newValues
    let common = Set(old.keys).intersection(Set(new.keys))
    return common.compactMap { key in
      guard let config = message.model.configs.first(where: { $0.key.label == key }) else { return nil }
      let oldVal = old[key]
      let newVal = new[key]
      let oldStr = configDisplayString(oldVal, config: config)
      let newStr = configDisplayString(newVal, config: config)
      let changed = oldStr != newStr
      return RowData(label: key, oldDisplay: oldStr, newDisplay: newStr, changed: changed)
    }.sorted { $0.label < $1.label }
  }

  var body: some View {
    HStack {
      Spacer()
      VStack(alignment: .leading, spacing: 4) {
        Text("설정 업데이트됨")
          .font(.caption).fontWeight(.semibold)
          .foregroundColor(colors.onTertiaryContainer)
        HStack(alignment: .top, spacing: 4) {
          // Keys
          VStack(alignment: .leading) {
            ForEach(rows, id: \.label) { row in
              Text("\(row.label):")
                .font(.caption2)
                .opacity(0.6)
                .lineLimit(1)
            }
          }
          // Values
          VStack(alignment: .leading) {
            ForEach(rows, id: \.label) { row in
              if !row.changed {
                Text(row.newDisplay).font(.caption2).lineLimit(1)
              } else {
                HStack(spacing: 2) {
                  Text(row.oldDisplay).font(.caption2).lineLimit(1)
                  Text("▸").font(.caption2)
                  Text(row.newDisplay)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(colors.primary)
                    .lineLimit(1)
                }
              }
            }
          }
        }
        .padding(.top, 4)
      }
      .padding(8)
      .background(colors.tertiaryContainer)
      .cornerRadius(4)
      Spacer()
    }
  }

  private func configDisplayString(_ value: Any?, config: Config) -> String {
    guard let v = value else { return "-" }
    if let f = v as? Float { return String(format: "%.2f", f) }
    if let d = v as? Double { return String(format: "%.2f", d) }
    if let i = v as? Int { return "\(i)" }
    if let b = v as? Bool { return b ? "true" : "false" }
    return "\(v)"
  }
}
