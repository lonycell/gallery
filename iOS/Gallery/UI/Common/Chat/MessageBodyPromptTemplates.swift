/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyPromptTemplates.kt

import SwiftUI

private let CARD_HEIGHT: CGFloat = 100

struct MessageBodyPromptTemplates: View {
  let message: ChatMessagePromptTemplates
  let task: Task
  var onPromptClicked: (PromptTemplate) -> Void = { _ in }

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  private var taskColor: Color {
    let idx = task.index >= 0 ? task.index % customColors.taskIconColors.count : 0
    return customColors.taskIconColors.isEmpty ? colors.primary : customColors.taskIconColors[idx]
  }

  var body: some View {
    VStack(spacing: 8) {
      Text("예시 프롬프트를 사용해 보세요")
        .font(.title3).fontWeight(.bold)
        .foregroundStyle(
          LinearGradient(
            colors: [taskColor.opacity(0.5), taskColor],
            startPoint: .leading, endPoint: .trailing
          )
        )
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)

      if message.showMakeYourOwn {
        Text("또는 직접 만들어 보세요")
          .font(.subheadline)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.top, -4)
      }

      ScrollView {
        VStack(spacing: 8) {
          ForEach(message.templates, id: \.title) { template in
            Button {
              onPromptClicked(template)
            } label: {
              ZStack {
                RoundedRectangle(cornerRadius: 24)
                  .fill(colors.surface)
                  .shadow(color: taskColor.opacity(0.3), radius: 2, y: 1)
                  .overlay(
                    RoundedRectangle(cornerRadius: 24)
                      .stroke(taskColor.opacity(0.3), lineWidth: 1)
                  )
                VStack(spacing: 0) {
                  Text(template.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                  Spacer()
                  Text(template.description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
              }
              .frame(height: CARD_HEIGHT)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(height: CGFloat(message.templates.count) * (CARD_HEIGHT + 8))
    }
    .padding(.top, 12)
  }
}
