// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/home/HomeScreen.kt

import SwiftUI

// MARK: - Animation constants
private let TASK_COUNT_ANIMATION_DURATION = 0.25
private let ANIMATION_INIT_DELAY = 0.0
private let TOP_APP_BAR_ANIMATION_DURATION = 0.6
private let TITLE_FIRST_LINE_ANIMATION_DURATION_MS = 600
private let TITLE_SECOND_LINE_ANIMATION_DURATION_MS = 600
private let TITLE_SECOND_LINE_ANIMATION_DURATION2_MS = 800
private let TITLE_SECOND_LINE_ANIMATION_START_MS =
  Int(Double(TITLE_FIRST_LINE_ANIMATION_DURATION_MS) * 0.5)
private let TASK_LIST_ANIMATION_START_MS = TITLE_SECOND_LINE_ANIMATION_START_MS + 110
private let TASK_CARD_ANIMATION_DELAY_OFFSET_MS = 100
private let TASK_CARD_ANIMATION_DURATION_MS = 600
private let CONTENT_COMPOSABLES_ANIMATION_DURATION_MS = 1200
private let CONTENT_COMPOSABLES_OFFSET_Y: CGFloat = 16

private let PREDEFINED_CATEGORY_ORDER = [Category.LLM.id, Category.EXPERIMENTAL.id]

/// The home screen: category tabs with task grid, drawer navigation, TOS gate.
/// Mirrors `HomeScreen`.
struct HomeScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  var enableAnimation: Bool
  var gm4: Bool = false
  // NOTE: TOS acceptance state managed here; TosViewModel equivalent provided inline.
  @State private var isTosAccepted: Bool
  @State private var showSettingsDialog = false

  @EnvironmentObject private var router: Router
  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  // Drawer state
  @State private var showDrawer = false

  // Model allowlist loading debounce
  @State private var loadingDelayed = false

  init(modelManagerViewModel: ModelManagerViewModel,
       enableAnimation: Bool = true,
       gm4: Bool = false) {
    self.modelManagerViewModel = modelManagerViewModel
    self.enableAnimation = enableAnimation
    self.gm4 = gm4
    // NOTE: reading TOS from dataStoreRepository synchronously, matching Android's
    // tosViewModel.getIsTosAccepted() on first composition.
    _isTosAccepted = State(initialValue: modelManagerViewModel.dataStoreRepository.isTosAccepted())
  }

  // Sorted category list
  private var sortedCategories: [CategoryInfo] {
    let tasks = modelManagerViewModel.uiState.tasks
    var categoryMap: [String: CategoryInfo] = [:]
    for task in tasks { categoryMap[task.category.id] = task.category }
    return categoryMap.keys.sorted { a, b in
      let ia = PREDEFINED_CATEGORY_ORDER.firstIndex(of: a)
      let ib = PREDEFINED_CATEGORY_ORDER.firstIndex(of: b)
      switch (ia, ib) {
      case let (ia?, ib?): return ia < ib
      case (.some, nil):   return true
      case (nil, .some):   return false
      default:
        let la = categoryMap[a]?.label ?? ""
        let lb = categoryMap[b]?.label ?? ""
        return la < lb
      }
    }.compactMap { categoryMap[$0] }
  }

  var body: some View {
    ZStack {
      if !isTosAccepted {
        // TOS gate
        // NOTE: AppTosDialog is owned by common/tos agent — call through it.
        // AppTosDialog(onTosAccepted: { ... })
        VStack {
          Text(Str.appName)
            .font(AppTypography.titleLarge)
          Text("Please accept the terms of service to continue.")
            .font(AppTypography.bodyMedium)
          Button("Accept") {
            isTosAccepted = true
            modelManagerViewModel.dataStoreRepository.acceptTos()
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
      } else {
        mainContent
      }
    }
    .sheet(isPresented: $showSettingsDialog) {
      SettingsDialog(
        curThemeOverride: modelManagerViewModel.readThemeOverride(),
        modelManagerViewModel: modelManagerViewModel,
        onDismissed: { showSettingsDialog = false }
      )
    }
    // Alert for allowlist load error
    .alert(
      modelManagerViewModel.uiState.loadingModelAllowlistError,
      isPresented: Binding(
        get: { !modelManagerViewModel.uiState.loadingModelAllowlistError.isEmpty },
        set: { if !$0 { modelManagerViewModel.clearLoadModelAllowlistError() } }
      )
    ) {
      Button("Retry") { modelManagerViewModel.loadModelAllowlist() }
      Button("Cancel") { modelManagerViewModel.clearLoadModelAllowlistError() }
    } message: {
      Text("Please check your internet connection and try again later.")
    }
    .task(id: modelManagerViewModel.uiState.loadingModelAllowlist) {
      // Debounce: only show spinner after 200ms of loading
      if modelManagerViewModel.uiState.loadingModelAllowlist {
        try? await Task.sleep(nanoseconds: 200_000_000)
        if modelManagerViewModel.uiState.loadingModelAllowlist {
          loadingDelayed = true
        }
      } else {
        loadingDelayed = false
      }
    }
  }

  @ViewBuilder
  private var mainContent: some View {
    if loadingDelayed {
      HStack(spacing: 8) {
        ProgressView()
          .scaleEffect(0.8)
        Text(Str.loadingModelList)
          .font(AppTypography.bodyMedium)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if !modelManagerViewModel.uiState.loadingModelAllowlist {
      homeBody
    }
  }

  @ViewBuilder
  private var homeBody: some View {
    NavigationStack {
      ZStack(alignment: .leading) {
        // Main content
        VStack(spacing: 0) {
          scrollableContent
        }
        .background(gm4 ? colors.surface : colors.surfaceContainer)
        .navigationTitle(Str.appName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button {
              withAnimation { showDrawer = true }
            } label: {
              Image(systemName: "line.horizontal.3")
            }
          }
        }

        // Side drawer overlay
        if showDrawer {
          Color.black.opacity(0.3)
            .ignoresSafeArea()
            .onTapGesture { withAnimation { showDrawer = false } }

          DrawerContent(
            onSettingsTapped: {
              showSettingsDialog = true
              withAnimation { showDrawer = false }
            },
            onModelsTapped: {
              withAnimation { showDrawer = false }
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                router.navigate(.modelManager)
              }
            }
          )
          .frame(maxWidth: 320)
          .frame(maxHeight: .infinity)
          .background(colors.surface)
          .transition(.move(edge: .leading))
          .zIndex(1)
        }
      }
    }
  }

  @ViewBuilder
  private var scrollableContent: some View {
    ScrollView {
      VStack(spacing: 0) {
        if gm4 {
          // Background star
          GeometryReader { geo in
            Image("bg_star")
              .resizable()
              .scaledToFill()
              .frame(width: geo.size.width * 1.5)
              .blur(radius: 35)
              .opacity(0.46)
              .offset(x: geo.size.width * 0.25, y: -geo.size.width * 0.1)
              .allowsHitTesting(false)
          }
          .frame(height: 0)
        }

        // Title section
        VStack(alignment: .leading, spacing: 8) {
          if gm4 {
            AppTitleGm4(enableAnimation: enableAnimation)
          } else {
            AppTitle(enableAnimation: enableAnimation)
          }
          IntroText(enableAnimation: enableAnimation, gm4: gm4)
          if gm4 {
            TryGm4IntroText(enableAnimation: enableAnimation)
          }
        }
        .padding(.horizontal, gm4 ? 24 : 40)
        .padding(.vertical, gm4 ? 0 : 48)
        .padding(.top, 24)
        .padding(.bottom, 16)

        // Category tabs
        if sortedCategories.count > 1 {
          CategoryTabHeader(
            sortedCategories: sortedCategories,
            enableAnimation: enableAnimation
          )
        }

        // Task list / grid pager
        TaskListPager(
          modelManagerViewModel: modelManagerViewModel,
          sortedCategories: sortedCategories,
          enableAnimation: enableAnimation,
          gm4: gm4,
          grid: gm4,
          onTaskTapped: { task in router.navigate(.modelList(taskId: task.id)) }
        )

        Spacer().frame(height: 32)
      }
    }
  }
}

// MARK: - Drawer

private struct DrawerContent: View {
  let onSettingsTapped: () -> Void
  let onModelsTapped: () -> Void

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    VStack(alignment: .leading) {
      HStack(spacing: 16) {
        SquareDrawerItem(
          label: Str.drawerSettingsLabel,
          description: Str.drawerSettingsDescription,
          systemImage: "gearshape",
          onClick: onSettingsTapped,
          iconGradient: LinearGradient(
            colors: customColors.taskBgGradientColors.indices.contains(2)
              ? customColors.taskBgGradientColors[2] : [colors.primary, colors.primaryContainer],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

        SquareDrawerItem(
          label: Str.drawerModelsLabel,
          description: Str.drawerModelsDescription,
          systemImage: "list.bullet.rectangle",
          onClick: onModelsTapped,
          iconGradient: LinearGradient(
            colors: customColors.taskBgGradientColors.indices.contains(1)
              ? customColors.taskBgGradientColors[1] : [colors.secondary, colors.secondaryContainer],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
      .padding(16)

      Spacer()
    }
  }
}

// MARK: - App title (non-gm4)

private struct AppTitle: View {
  let enableAnimation: Bool

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    let titleColor = customColors.appTitleGradientColors.last ?? colors.primary
    let fontSize: CGFloat = UIScreen.main.bounds.width * 0.12

    VStack(alignment: .leading, spacing: 0) {
      // First line
      ZStack(alignment: .leading) {
        if enableAnimation {
          SwipingText(
            text: Str.appNameFirstPart,
            style: AppFont.font(size: fontSize, weight: .medium),
            color: titleColor,
            animationDelay: ANIMATION_INIT_DELAY,
            animationDurationMs: TITLE_FIRST_LINE_ANIMATION_DURATION_MS
          )
        }
        SwipingText(
          text: Str.appNameFirstPart,
          style: AppFont.font(size: fontSize, weight: .medium),
          color: colors.onSurface,
          animationDelay: enableAnimation
            ? ANIMATION_INIT_DELAY + Double(TITLE_FIRST_LINE_ANIMATION_DURATION_MS) * 0.3 / 1000
            : 0,
          animationDurationMs: enableAnimation ? TITLE_FIRST_LINE_ANIMATION_DURATION_MS : 0
        )
      }
      .accessibilityHidden(true)

      // Second line
      ZStack(alignment: .leading) {
        let delay = Double(TITLE_SECOND_LINE_ANIMATION_START_MS) / 1000
        if enableAnimation {
          SwipingText(
            text: Str.appNameSecondPart,
            style: AppFont.font(size: fontSize, weight: .medium),
            color: titleColor,
            animationDelay: delay,
            animationDurationMs: TITLE_SECOND_LINE_ANIMATION_DURATION_MS
          )
          .offset(y: -16)
        }
        RevealingText(
          text: Str.appNameSecondPart,
          style: AppFont.font(size: fontSize, weight: .medium),
          animationDelay: enableAnimation
            ? delay + Double(TITLE_SECOND_LINE_ANIMATION_DURATION_MS) * 0.9 / 1000
            : 0,
          animationDurationMs: enableAnimation ? TITLE_SECOND_LINE_ANIMATION_DURATION2_MS : 0
        )
        .offset(x: -16, y: -16)
        // Gradient overlay on the revealing text
        .overlay(
          LinearGradient(
            colors: customColors.appTitleGradientColors,
            startPoint: .leading,
            endPoint: .trailing
          )
          .blendMode(.sourceAtop)
        )
      }
      .accessibilityHidden(true)

      // Accessibility label
      Text("\(Str.appNameFirstPart) \(Str.appNameSecondPart)")
        .hidden()
        .accessibilityLabel("\(Str.appNameFirstPart) \(Str.appNameSecondPart)")
    }
  }
}

// MARK: - App title (gm4)

private struct AppTitleGm4: View {
  let enableAnimation: Bool

  @Environment(\.galleryColors) private var colors

  var body: some View {
    let parts = AttributedString(Str.appNameFirstPart + " " + Str.appNameSecondPart)
    RevealingText(
      text: "\(Str.appNameFirstPart) \(Str.appNameSecondPart)",
      style: AppFont.font(size: 24, weight: .medium),
      animationDelay: 0,
      animationDurationMs: enableAnimation
        ? (TITLE_FIRST_LINE_ANIMATION_DURATION_MS + TITLE_SECOND_LINE_ANIMATION_DURATION_MS)
        : 0
    )
  }
}

// MARK: - Intro text

private struct IntroText: View {
  let enableAnimation: Bool
  let gm4: Bool

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  @State private var opacity: Double = 0
  @State private var offsetY: CGFloat = CONTENT_COMPOSABLES_OFFSET_Y

  var body: some View {
    Group {
      if gm4 {
        (Text("Discover the power of on-device AI models from the ")
          + Text("LiteRT community").underline()
            .foregroundStyle(customColors.linkColor)
          + Text(", featuring the all-new ")
          + Text("Gemma 4").underline()
            .foregroundStyle(customColors.linkColor)
          + Text("."))
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurface)
      } else {
        (Text("\(Str.appIntro) ")
          + Text(Str.litertCommunityLabel).underline()
            .foregroundStyle(customColors.linkColor))
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurface)
      }
    }
    .opacity(opacity)
    .offset(y: offsetY)
    .onAppear {
      guard enableAnimation else {
        opacity = 1; offsetY = 0; return
      }
      let delay = Double(TITLE_SECOND_LINE_ANIMATION_START_MS) / 1000
      withAnimation(.easeOut(duration: Double(CONTENT_COMPOSABLES_ANIMATION_DURATION_MS) / 1000)
        .delay(delay)) {
        opacity = 1
        offsetY = 0
      }
    }
  }
}

// MARK: - Try Gm4 intro text

private struct TryGm4IntroText: View {
  let enableAnimation: Bool

  @Environment(\.galleryColors) private var colors
  @State private var opacity: Double = 0
  @State private var offsetY: CGFloat = CONTENT_COMPOSABLES_OFFSET_Y

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        // NOTE: gemma_logo is a vector drawable; map to asset or SF symbol.
        Image(systemName: "star.circle.fill")
          .frame(width: 24, height: 24)
          .foregroundStyle(colors.primary)

        Text("Try Gemma 4 today")
          .font(AppFont.font(size: 20, weight: .medium))
          .foregroundStyle(colors.onSurface)
      }
      .padding(.top, 24)

      Text("Gemma 4 E2B & E4B are here! Try them in AI Chat, Agent Skills, or the use cases below.")
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurface)
    }
    .opacity(opacity)
    .offset(y: offsetY)
    .onAppear {
      guard enableAnimation else { opacity = 1; offsetY = 0; return }
      let delay = Double(TITLE_SECOND_LINE_ANIMATION_START_MS) / 1000
      withAnimation(.easeOut(duration: Double(CONTENT_COMPOSABLES_ANIMATION_DURATION_MS) / 1000)
        .delay(delay)) {
        opacity = 1; offsetY = 0
      }
    }
  }
}

// MARK: - Category tabs

private struct CategoryTabHeader: View {
  let sortedCategories: [CategoryInfo]
  let enableAnimation: Bool
  @State private var selectedIndex = 0
  @State private var opacity: Double = 0
  @State private var offsetY: CGFloat = CONTENT_COMPOSABLES_OFFSET_Y

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  // Expose selection to parent via binding would be cleaner; here driven internally via pager below.
  var onCategorySelected: ((Int) -> Void)? = nil

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 16) {
        Spacer().frame(width: 8)
        ForEach(Array(sortedCategories.enumerated()), id: \.offset) { index, category in
          Button(action: { onCategorySelected?(index) }) {
            Text(category.label ?? Str.categoryUnlabeled)
              .font(AppTypography.labelLarge)
              .foregroundStyle(selectedIndex == index ? .white : colors.onSurfaceVariant)
              .padding(.horizontal, 16)
              .frame(height: 40)
          }
          .background(
            Capsule()
              .fill(selectedIndex == index ? customColors.tabHeaderBgColor : Color.clear)
          )
        }
        Spacer().frame(width: 8)
      }
    }
    .padding(.bottom, 32)
    .opacity(opacity)
    .offset(y: offsetY)
    .onAppear {
      guard enableAnimation else { opacity = 1; offsetY = 0; return }
      let delay = Double(TASK_LIST_ANIMATION_START_MS) / 1000
      withAnimation(.easeOut(duration: Double(CONTENT_COMPOSABLES_ANIMATION_DURATION_MS) / 1000)
        .delay(delay)) {
        opacity = 1; offsetY = 0
      }
    }
  }
}

// MARK: - Task list pager

private struct TaskListPager: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let sortedCategories: [CategoryInfo]
  let enableAnimation: Bool
  let gm4: Bool
  let grid: Bool
  let onTaskTapped: (Task) -> Void

  @State private var selectedPage = 0
  @State private var initialAnimationDone = false

  var body: some View {
    VStack(spacing: 0) {
      // Category selection tabs (driven by pager)
      CategoryTabHeader(
        sortedCategories: sortedCategories,
        enableAnimation: enableAnimation,
        onCategorySelected: { selectedPage = $0 }
      )

      // Highlighted tiles for gm4
      if gm4 {
        VStack(spacing: 10) {
          let chatToDesc: [String: String] = [
            BuiltInTaskId.LLM_CHAT: "Chat with the latest Gemma 4 model today",
            BuiltInTaskId.LLM_AGENT_CHAT: "Have Gemma 4 complete agentic tasks for\u{00A0}you",
          ]
          ForEach([BuiltInTaskId.LLM_CHAT, BuiltInTaskId.LLM_AGENT_CHAT], id: \.self) { taskId in
            if let task = modelManagerViewModel.getTaskById(taskId) {
              TaskCard(
                task: task,
                index: 0,
                animate: !initialAnimationDone && enableAnimation,
                description: chatToDesc[taskId] ?? "",
                square: false,
                onClick: { onTaskTapped(task) }
              )
              .frame(maxWidth: .infinity)
            }
          }

          Text("Explore other use cases")
            .font(AppFont.font(size: 20, weight: .medium))
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
      }

      // Category pages (tab view)
      TabView(selection: $selectedPage) {
        ForEach(Array(sortedCategories.enumerated()), id: \.offset) { pageIndex, category in
          let tasks = modelManagerViewModel.uiState.tasksByCategory[category.id] ?? []
          Group {
            if grid {
              LazyVStack(spacing: 16) {
                ForEach(Array(stride(from: 0, to: tasks.count, by: 2)), id: \.self) { i in
                  HStack(spacing: 16) {
                    TaskCard(
                      task: tasks[i],
                      index: i,
                      animate: (pageIndex == 0 || pageIndex == 1) && !initialAnimationDone && enableAnimation,
                      onClick: { onTaskTapped(tasks[i]) },
                      square: true
                    )
                    if i + 1 < tasks.count {
                      TaskCard(
                        task: tasks[i + 1],
                        index: i + 1,
                        animate: (pageIndex == 0 || pageIndex == 1) && !initialAnimationDone && enableAnimation,
                        onClick: { onTaskTapped(tasks[i + 1]) },
                        square: true
                      )
                    } else {
                      Spacer().frame(maxWidth: .infinity)
                    }
                  }
                }
              }
              .padding(4)
            } else {
              LazyVStack(spacing: 10) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                  TaskCard(
                    task: task,
                    index: index,
                    animate: (pageIndex == 0 || pageIndex == 1) && !initialAnimationDone && enableAnimation,
                    onClick: { onTaskTapped(task) },
                    square: false
                  )
                  .frame(maxWidth: .infinity)
                }
              }
              .padding(4)
            }
          }
          .padding(.horizontal, 20)
          .tag(pageIndex)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(minHeight: 200)
      .fixedSize(horizontal: false, vertical: true)
    }
    .task {
      let delay = Double((TASK_CARD_ANIMATION_DURATION_MS + TASK_CARD_ANIMATION_DELAY_OFFSET_MS) * 5) / 1000
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      initialAnimationDone = true
    }
  }
}

// MARK: - Task card

private struct TaskCard: View {
  let task: Task
  let index: Int
  let animate: Bool
  let onClick: () -> Void
  var description: String = ""
  var square: Bool = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  @State private var opacity: Double = 0
  @State private var modelCountLabel: String = ""
  @State private var modelCountLabelVisible = true

  private var modelCount: Int { task.models.count }

  private var cardBgColor: Color {
    (description.isEmpty && !square) ? customColors.taskCardBgColor : colors.surfaceContainer
  }

  var body: some View {
    Button(action: onClick) {
      Group {
        if square {
          squareLayout
        } else {
          rowLayout
        }
      }
    }
    .buttonStyle(.plain)
    .background(cardBgColor)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .opacity(animate ? opacity : 1)
    .onAppear {
      modelCountLabel = modelCountString()
      guard animate else { opacity = 1; return }
      let delay = Double(TASK_LIST_ANIMATION_START_MS + index * TASK_CARD_ANIMATION_DELAY_OFFSET_MS) / 1000
      withAnimation(.easeOut(duration: Double(TASK_CARD_ANIMATION_DURATION_MS) / 1000).delay(delay)) {
        opacity = 1
      }
    }
    .onChange(of: modelCount) { _, _ in
      let newLabel = modelCountString()
      guard !modelCountLabel.isEmpty else { modelCountLabel = newLabel; return }
      withAnimation(.easeOut(duration: TASK_COUNT_ANIMATION_DURATION)) {
        modelCountLabelVisible = false
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + TASK_COUNT_ANIMATION_DURATION) {
        modelCountLabel = newLabel
        withAnimation(.easeIn(duration: TASK_COUNT_ANIMATION_DURATION)) {
          modelCountLabelVisible = true
        }
      }
    }
    .accessibilityLabel(String(format: Str.cdTaskCard, task.label, modelCount))
  }

  private func modelCountString() -> String {
    modelCount == 1 ? "1 Model" : "\(modelCount) Models"
  }

  @ViewBuilder
  private var squareLayout: some View {
    VStack(alignment: .leading, spacing: 16) {
      TaskIcon(task: task, width: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(modelCountLabel)
          .font(AppFont.font(size: 12))
          .foregroundStyle(colors.onSurfaceVariant)
          .opacity(modelCountLabelVisible ? 1 : 0)
          .accessibilityHidden(true)
        Text(task.label)
          .font(AppTypography.titleMedium)
          .foregroundStyle(colors.onSurface)
        Text(task.shortDescription)
          .font(AppFont.font(size: 12))
          .lineSpacing(2)
          .foregroundStyle(colors.onSurfaceVariant)
          .lineLimit(2)
          .minimumScaleFactor(0.7)
          .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
  }

  @ViewBuilder
  private var rowLayout: some View {
    HStack {
      if !description.isEmpty {
        // Description variant (gm4 highlight cards)
        TaskIcon(task: task, width: 40)

        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(task.label)
              .font(AppTypography.titleMedium)
              .foregroundStyle(colors.onSurface)
            Spacer()
            if task.newFeature {
              Text("New")
                .font(AppTypography.labelLarge)
                .foregroundStyle(customColors.newFeatureTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(customColors.newFeatureContainerColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .offset(x: 6, y: -6)
            }
          }
          Text(description)
            .font(AppFont.font(size: 12))
            .lineSpacing(3)
            .foregroundStyle(colors.onSurfaceVariant)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
      } else {
        // Standard row variant
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            Text(task.label)
              .font(AppTypography.titleMedium)
              .foregroundStyle(colors.onSurface)
            if task.experimental {
              Image(systemName: "flask")
                .frame(width: 16, height: 16)
                .foregroundStyle(colors.onSurfaceVariant)
            }
          }
          Text(modelCountLabel)
            .font(AppTypography.bodyMedium)
            .foregroundStyle(colors.onSurfaceVariant)
            .opacity(modelCountLabelVisible ? 1 : 0)
            .accessibilityHidden(true)
        }

        Spacer()

        TaskIcon(task: task, width: 40)
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 20)
  }
}
