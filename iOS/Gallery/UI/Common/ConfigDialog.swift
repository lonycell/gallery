/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ConfigDialog.kt

import SwiftUI

// MARK: - ConfigDialog

/// Displays a configuration dialog allowing users to modify settings through various
/// input controls. Mirrors `ConfigDialog` composable.
struct ConfigDialog: View {
  let title: String
  let configs: [Config]
  let initialValues: [String: Any]
  let onDismissed: () -> Void
  let onOk: (_ values: [String: Any], _ oldSystemPrompt: String, _ newSystemPrompt: String) -> Void
  var okBtnLabel: String = "OK"
  var subtitle: String = ""
  var showCancel: Bool = true
  var showSystemPromptEditorTab: Bool = false
  var defaultSystemPrompt: String = ""
  var curSystemPrompt: String = ""

  @State private var values: [String: Any]
  @State private var selectedTabIndex: Int = 0
  @State private var systemPrompt: String
  private let savedSystemPrompt: String

  @Environment(\.galleryColors) private var colors

  init(
    title: String,
    configs: [Config],
    initialValues: [String: Any],
    onDismissed: @escaping () -> Void,
    onOk: @escaping ([String: Any], String, String) -> Void,
    okBtnLabel: String = "OK",
    subtitle: String = "",
    showCancel: Bool = true,
    showSystemPromptEditorTab: Bool = false,
    defaultSystemPrompt: String = "",
    curSystemPrompt: String = ""
  ) {
    self.title = title
    self.configs = configs
    self.initialValues = initialValues
    self.onDismissed = onDismissed
    self.onOk = onOk
    self.okBtnLabel = okBtnLabel
    self.subtitle = subtitle
    self.showCancel = showCancel
    self.showSystemPromptEditorTab = showSystemPromptEditorTab
    self.defaultSystemPrompt = defaultSystemPrompt
    self.curSystemPrompt = curSystemPrompt
    self.savedSystemPrompt = curSystemPrompt
    _values = State(initialValue: initialValues)
    _systemPrompt = State(initialValue: curSystemPrompt)
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea()
        .onTapGesture { onDismissed() }

      VStack(spacing: 0) {
        RoundedRectangle(cornerRadius: 16)
          .fill(colors.surface)
          .overlay(
            VStack(alignment: .leading, spacing: 16) {
              // Title + subtitle
              VStack(alignment: .leading, spacing: 4) {
                Text(title)
                  .font(AppTypography.titleLarge)
                  .foregroundStyle(colors.onSurface)
                if !subtitle.isEmpty {
                  Text(subtitle)
                    .font(AppTypography.labelSmall)
                    .foregroundStyle(colors.onSurfaceVariant)
                }
              }

              // Tabs
              if showSystemPromptEditorTab {
                HStack(spacing: 0) {
                  ForEach([Str.configDialogTabModelConfigs, Str.configDialogTabSystemPrompt], id: \.self) { label in
                    let index = label == Str.configDialogTabModelConfigs ? 0 : 1
                    Button {
                      selectedTabIndex = index
                    } label: {
                      VStack(spacing: 4) {
                        Text(label)
                          .font(AppTypography.labelLarge)
                          .foregroundStyle(selectedTabIndex == index ? colors.primary : colors.onSurfaceVariant)
                        Rectangle()
                          .fill(selectedTabIndex == index ? colors.primary : Color.clear)
                          .frame(height: 2)
                      }
                    }
                    .frame(maxWidth: .infinity)
                  }
                }
              }

              // Content
              if selectedTabIndex == 0 {
                ScrollView {
                  VStack(alignment: .leading, spacing: 16) {
                    ConfigEditorsPanel(configs: configs, values: $values)
                  }
                }
                .frame(maxHeight: 400)
              } else {
                TextEditor(text: $systemPrompt)
                  .font(AppTypography.bodySmall)
                  .foregroundStyle(colors.onSurface)
                  .frame(minHeight: 120, maxHeight: 300)
                  .overlay(
                    RoundedRectangle(cornerRadius: 4)
                      .stroke(colors.outline, lineWidth: 1)
                  )
                  .overlay(alignment: .topLeading) {
                    if systemPrompt.isEmpty {
                      Text(Str.systemPromptPlaceholder)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(colors.onSurfaceVariant.opacity(0.6))
                        .padding(8)
                        .allowsHitTesting(false)
                    }
                  }
              }

              // Button row
              HStack {
                if showSystemPromptEditorTab && selectedTabIndex == 1 {
                  Button(Str.restoreDefault) {
                    systemPrompt = defaultSystemPrompt
                  }
                  .font(AppTypography.labelLarge)
                  .foregroundStyle(colors.primary)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 8)
                  .overlay(
                    RoundedRectangle(cornerRadius: 20)
                      .stroke(colors.outline, lineWidth: 1)
                  )
                }
                Spacer()
                if showCancel {
                  Button(Str.cancel) { onDismissed() }
                    .font(AppTypography.labelLarge)
                    .foregroundStyle(colors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                Button(okBtnLabel) {
                  onOk(values, savedSystemPrompt, systemPrompt)
                }
                .font(AppTypography.labelLarge)
                .foregroundStyle(colors.onPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(colors.primary, in: Capsule())
              }
            }
            .padding(20)
          )
          .padding(.horizontal, 24)
      }
    }
  }
}

// MARK: - ConfigEditorsPanel

/// Displays a list of config editor rows. Mirrors `ConfigEditorsPanel`.
struct ConfigEditorsPanel: View {
  let configs: [Config]
  @Binding var values: [String: Any]

  var body: some View {
    ForEach(configs, id: \.key.id) { config in
      if let label = config as? LabelConfig {
        LabelRow(config: label, values: $values)
      } else if let slider = config as? NumberSliderConfig {
        NumberSliderRow(config: slider, values: $values)
      } else if let toggle = config as? BooleanSwitchConfig {
        BooleanSwitchRow(config: toggle, values: $values)
      } else if let segmented = config as? SegmentedButtonConfig {
        SegmentedButtonRow(config: segmented, values: $values)
      } else if let selector = config as? BottomSheetSelectorConfig {
        BottomSheetSelectorRow(config: selector, values: $values)
      }
    }
  }
}

// MARK: - LabelRow

struct LabelRow: View {
  let config: LabelConfig
  @Binding var values: [String: Any]

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(config.key.label)
        .font(AppTypography.titleSmall)
        .foregroundStyle(colors.onSurface)
      Text((values[config.key.label] as? String) ?? "")
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurface)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - NumberSliderRow

private func sliderDisplayValue(valueType: ValueType, value: Float) -> String {
  switch valueType {
  case .float: return String(format: "%.2f", value)
  case .int:   return "\(Int(value))"
  default:     return ""
  }
}

struct NumberSliderRow: View {
  let config: NumberSliderConfig
  @Binding var values: [String: Any]

  @State private var textInput: String = ""
  @State private var isFocused: Bool = false
  @Environment(\.galleryColors) private var colors

  var currentSliderValue: Float {
    (values[config.key.label] as? Float) ?? config.sliderMin
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      let minStr = sliderDisplayValue(valueType: config.valueType, value: config.sliderMin)
      let maxStr = sliderDisplayValue(valueType: config.valueType, value: config.sliderMax)
      Text("\(config.key.label) (\(minStr)-\(maxStr))")
        .font(AppTypography.titleSmall)
        .foregroundStyle(colors.onSurface)

      HStack(spacing: 8) {
        Slider(
          value: Binding(
            get: { currentSliderValue },
            set: { newVal in
              values[config.key.label] = newVal
              if !isFocused {
                textInput = sliderDisplayValue(valueType: config.valueType, value: newVal)
              }
            }
          ),
          in: config.sliderMin...config.sliderMax
        )

        // Inline text field
        TextField("", text: $textInput)
          .keyboardType(.decimalPad)
          .font(AppTypography.bodySmall)
          .foregroundStyle(colors.onSurface)
          .frame(width: 72)
          .padding(8)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(isFocused ? colors.primary : colors.outline,
                      lineWidth: isFocused ? 2 : 1)
          )
          .onAppear {
            textInput = sliderDisplayValue(valueType: config.valueType, value: currentSliderValue)
          }
          .onChange(of: textInput) { newText in
            if let f = Float(newText) {
              let clamped = min(max(f, config.sliderMin), config.sliderMax)
              values[config.key.label] = clamped
            }
          }
      }

      // MAX_TOKENS warning
      if config.key == ConfigKeys.MAX_TOKENS && currentSliderValue >= 10000 {
        Text(Str.maxTokensWarningMessage)
          .font(AppTypography.bodySmall)
          .foregroundStyle(colors.error)
          .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - BooleanSwitchRow

struct BooleanSwitchRow: View {
  let config: BooleanSwitchConfig
  @Binding var values: [String: Any]

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(config.key.label)
        .font(AppTypography.titleSmall)
        .foregroundStyle(colors.onSurface)
      Toggle("", isOn: Binding(
        get: { (values[config.key.label] as? Bool) ?? false },
        set: { values[config.key.label] = $0 }
      ))
      .labelsHidden()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - SegmentedButtonRow

struct SegmentedButtonRow: View {
  let config: SegmentedButtonConfig
  @Binding var values: [String: Any]

  @State private var selectionStates: [Bool] = []
  @Environment(\.galleryColors) private var colors

  private func initStates() {
    let selected = ((values[config.key.label] as? String) ?? "")
      .split(separator: ",").map(String.init)
    selectionStates = config.options.map { selected.contains($0) }
    if selectionStates.allSatisfy({ !$0 }), !config.options.isEmpty {
      selectionStates[0] = true
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(config.key.label)
        .font(AppTypography.titleSmall)
        .foregroundStyle(colors.onSurface)

      if config.allowMultiple {
        // Multi-select: show as a wrapping row of toggle chips
        FlowLayout(spacing: 8) {
          ForEach(Array(config.options.enumerated()), id: \.offset) { idx, option in
            Button {
              var newStates = selectionStates
              let selectedCount = newStates.filter { $0 }.count
              if !(selectedCount == 1 && newStates[idx]) {
                newStates[idx].toggle()
              }
              selectionStates = newStates
              commitSelection()
            } label: {
              Text(option)
                .font(AppTypography.labelMedium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                  selectionStates.indices.contains(idx) && selectionStates[idx]
                    ? colors.secondaryContainer : Color.clear,
                  in: Capsule()
                )
                .overlay(Capsule().stroke(colors.outline, lineWidth: 1))
                .foregroundStyle(colors.onSurface)
            }
          }
        }
      } else {
        // Single-select: Picker with segmented style
        Picker("", selection: Binding(
          get: {
            selectionStates.indices.first(where: { selectionStates[$0] }) ?? 0
          },
          set: { newIdx in
            selectionStates = config.options.indices.map { $0 == newIdx }
            commitSelection()
          }
        )) {
          ForEach(Array(config.options.enumerated()), id: \.offset) { idx, option in
            Text(option).tag(idx)
          }
        }
        .pickerStyle(.segmented)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { initStates() }
  }

  private func commitSelection() {
    let result = config.options.enumerated()
      .filter { selectionStates.indices.contains($0.offset) && selectionStates[$0.offset] }
      .map(\.element)
      .joined(separator: ",")
    values[config.key.label] = result
  }
}

// MARK: - BottomSheetSelectorRow

struct BottomSheetSelectorRow: View {
  let config: BottomSheetSelectorConfig
  @Binding var values: [String: Any]
  var showLabel: Bool = true
  var onSelected: (BottomSheetSelectorItem) -> Void = { _ in }

  @State private var selectedOption: BottomSheetSelectorItem?
  @State private var showSheet: Bool = false
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if showLabel {
        Text(config.key.label)
          .font(AppTypography.titleSmall)
          .foregroundStyle(colors.onSurface)
      }
      Button {
        showSheet = true
      } label: {
        HStack {
          Text(selectedOption?.label ?? "-")
            .font(AppTypography.labelLarge)
            .foregroundStyle(colors.onSurface)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Image(systemName: "chevron.down")
            .foregroundStyle(colors.onSurface)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .overlay(Capsule().stroke(colors.outline, lineWidth: 1))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      selectedOption = config.options.first { $0.label == (config.defaultValue as? String) }
        ?? config.options.first
    }
    .sheet(isPresented: $showSheet) {
      VStack(alignment: .leading, spacing: 0) {
        if let title = config.bottomSheetTitle {
          Text(title)
            .font(AppTypography.titleLarge)
            .foregroundStyle(colors.onSurface)
            .padding(16)
        }
        ScrollView {
          VStack(spacing: 0) {
            ForEach(config.options, id: \.label) { option in
              Button {
                selectedOption = option
                values[config.key.label] = option.label
                onSelected(option)
                showSheet = false
              } label: {
                HStack(spacing: 16) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(colors.secondary)
                    .opacity(option.label == selectedOption?.label ? 1 : 0)
                  Text(option.label)
                    .font(AppTypography.labelLarge)
                    .foregroundStyle(colors.onSurface)
                  Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
              }
            }
          }
        }
      }
      .presentationDetents([.medium, .large])
    }
  }
}

// MARK: - FlowLayout helper (wrapping HStack)

private struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let containerWidth = proposal.width ?? .infinity
    var height: CGFloat = 0
    var rowWidth: CGFloat = 0
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if rowWidth + size.width > containerWidth && rowWidth > 0 {
        height += rowHeight + spacing
        rowWidth = 0; rowHeight = 0
      }
      rowWidth += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    height += rowHeight
    return CGSize(width: containerWidth, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX && x > bounds.minX {
        y += rowHeight + spacing
        x = bounds.minX; rowHeight = 0
      }
      sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
