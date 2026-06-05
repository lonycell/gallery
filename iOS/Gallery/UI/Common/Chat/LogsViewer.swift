/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/LogsViewer.kt

import SwiftUI

struct LogsViewer: View {
  let logs: [LogMessage]
  var onDismissRequest: () -> Void = {}

  @State private var filterText = ""
  @State private var selectedLevels: Set<LogMessageLevel> = [.info, .warning, .error]
  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var filteredLogs: [LogMessage] {
    logs.filter { log in
      log.message.localizedCaseInsensitiveContains(filterText.isEmpty ? log.message : filterText)
        && selectedLevels.contains(log.level)
    }
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Search bar
        HStack {
          Image(systemName: "magnifyingglass").foregroundColor(colors.onSurfaceVariant)
          TextField(Str.logsViewerFilterTextInputPlaceholder, text: $filterText)
          if !filterText.isEmpty {
            Button { filterText = "" } label: {
              Image(systemName: "xmark.circle.fill").foregroundColor(colors.onSurfaceVariant)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.surfaceContainer)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 12)

        // Level filter
        HStack(spacing: 0) {
          ForEach([LogMessageLevel.info, .warning, .error], id: \.self) { level in
            let selected = selectedLevels.contains(level)
            Button {
              if selected { selectedLevels.remove(level) } else { selectedLevels.insert(level) }
            } label: {
              Text(level.displayName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(selected ? colors.secondaryContainer : colors.surface)
                .overlay(Rectangle().stroke(colors.outline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)

        // Logs list
        if filteredLogs.isEmpty {
          Text(Str.logsViewerNoMatchingLogs)
            .font(.body)
            .foregroundColor(colors.onSurfaceVariant)
            .padding()
          Spacer()
        } else {
          List(filteredLogs.indices, id: \.self) { i in
            LogItemView(log: filteredLogs[i])
              .listRowSeparator(.hidden)
              .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }
          .listStyle(.plain)
        }
      }
      .padding(.top, 16)
      .navigationTitle(Str.logsViewerTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(Str.close) { onDismissRequest() }
        }
      }
    }
  }
}

private struct LogItemView: View {
  let log: LogMessage
  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var iconName: String {
    switch log.level {
    case .info: return "info.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .error: return "xmark.circle.fill"
    }
  }

  private var iconColor: Color {
    switch log.level {
    case .info: return colors.outlineVariant
    case .warning: return customColors.warningTextColor
    case .error: return customColors.errorTextColor
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: iconName)
        .foregroundColor(iconColor)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 4) {
        if !log.source.isEmpty {
          let location = log.lineNumber >= 0 ? "\(log.source):\(log.lineNumber)" : log.source
          Text(location)
            .font(.caption2)
            .foregroundColor(colors.onSurfaceVariant.opacity(0.7))
        }
        Text(log.message)
          .font(.body)
      }
    }
  }
}

private extension LogMessageLevel {
  var displayName: String {
    switch self {
    case .info: return "Info"
    case .warning: return "Warning"
    case .error: return "Error"
    }
  }
}
