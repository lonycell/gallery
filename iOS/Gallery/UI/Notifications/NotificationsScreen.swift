// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of ui/notifications/NotificationsScreen.kt
//
// Android's Hilt-injected NotificationsViewModel is folded directly into this
// file as a lightweight @MainActor ObservableObject, exactly mirroring the
// Kotlin nested class pattern. The screen lists scheduled notifications from
// NotificationScheduleManager grouped by channelName, with collapse/expand and
// a confirmation-dialog delete flow.

import SwiftUI

// MARK: - NotificationsViewModel

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var notifications: [ScheduledNotification] = []

    private let scheduleManager: NotificationScheduleManager

    init(scheduleManager: NotificationScheduleManager) {
        self.scheduleManager = scheduleManager
        notifications = scheduleManager.notifications
    }

    func removeNotification(id: String) {
        scheduleManager.removeNotification(id: id)
        notifications = scheduleManager.notifications
    }
}

// MARK: - NotificationsScreen

/// A screen that lists scheduled notifications grouped by channel.
/// Collapsed/expanded per group. Delete triggers a confirmation alert.
///
/// Accepts `navigateUp` (a closure) so the NavHost wires back-navigation.
struct NotificationsScreen: View {
    @ObservedObject var viewModel: NotificationsViewModel
    let navigateUp: () -> Void

    @State private var notificationToDelete: ScheduledNotification? = nil
    @State private var expandedGroups: [String: Bool] = [:]

    @Environment(\.galleryColors) private var colors
    @Environment(\.customColors) private var customColors

    private var groupedNotifications: [(key: String, value: [ScheduledNotification])] {
        let grouped = Dictionary(grouping: viewModel.notifications) {
            $0.channelName.isEmpty ? "Default Channel" : $0.channelName
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            colors.surfaceContainer.ignoresSafeArea()

            if viewModel.notifications.isEmpty {
                VStack {
                    Spacer()
                    Text(Str.notificationsEmptyState)
                        .font(AppTypography.bodyLarge)
                        .foregroundColor(colors.onSurfaceVariant)
                    Spacer()
                }
            } else {
                List {
                    ForEach(groupedNotifications, id: \.key) { group in
                        Section {
                            if expandedGroups[group.key] ?? true {
                                ForEach(group.value) { notification in
                                    NotificationItem(
                                        notification: notification,
                                        onDeleteClick: { notificationToDelete = notification }
                                    )
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        } header: {
                            GroupHeader(
                                name: group.key,
                                isExpanded: expandedGroups[group.key] ?? true,
                                onToggle: {
                                    let current = expandedGroups[group.key] ?? true
                                    expandedGroups[group.key] = !current
                                }
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .background(colors.surfaceContainer)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(
            "\(Str.notificationsTitle) (\(viewModel.notifications.count))"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: navigateUp) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: navigateUp) {
                    Image(systemName: "xmark")
                        .foregroundColor(colors.onSurface)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert(
            Str.notificationsDeleteDialogTitle,
            isPresented: Binding(
                get: { notificationToDelete != nil },
                set: { if !$0 { notificationToDelete = nil } }
            ),
            presenting: notificationToDelete
        ) { notification in
            Button(Str.delete, role: .destructive) {
                viewModel.removeNotification(id: notification.id)
                notificationToDelete = nil
            }
            Button(Str.cancel, role: .cancel) {
                notificationToDelete = nil
            }
        } message: { notification in
            Text(String(format: Str.notificationsDeleteDialogContent
                .replacingOccurrences(of: "%s", with: "%@"), notification.title))
        }
    }
}

// MARK: - GroupHeader

private struct GroupHeader: View {
    let name: String
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.galleryColors) private var colors

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Text(name)
                    .font(AppTypography.titleMedium)
                    .fontWeight(.bold)
                    .foregroundColor(colors.onSurface)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(colors.onSurfaceVariant)
                    .font(.system(size: 14))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(colors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .textCase(nil)   // Suppress List section header auto-uppercasing
    }
}

// MARK: - NotificationItem

struct NotificationItem: View {
    let notification: ScheduledNotification
    let onDeleteClick: () -> Void

    @Environment(\.galleryColors) private var colors
    @Environment(\.customColors) private var customColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(notification.title)
                .font(AppTypography.titleMedium)
                .fontWeight(.bold)
                .foregroundColor(colors.onSurface)

            Spacer().frame(height: 4)

            Text(notification.message)
                .font(AppTypography.bodyMedium)
                .foregroundColor(colors.onSurface)

            Spacer().frame(height: 8)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    let timeStr = String(format: "%02d:%02d",
                                        Int(notification.hour),
                                        Int(notification.minute))
                    Text(String(format: Str.notificationsTimeLabel
                            .replacingOccurrences(of: "%s", with: "%@"), timeStr))
                        .font(AppTypography.labelMedium)
                        .foregroundColor(colors.onSurfaceVariant)

                    if notification.repeatDaily != true,
                       let y = notification.year,
                       let mo = notification.month,
                       let d = notification.day {
                        let dateStr = "\(y)/\(mo)/\(d)"
                        Text(String(format: Str.notificationsDateLabel
                                .replacingOccurrences(of: "%s", with: "%@"), dateStr))
                            .font(AppTypography.labelMedium)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }

                Spacer()

                Text(notification.repeatDaily == true
                     ? Str.notificationsRepeatDaily
                     : Str.notificationsRepeatOneTime)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(colors.onSurfaceVariant)
            }

            // Delete button
            HStack {
                Spacer()
                Button(action: onDeleteClick) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                        Text(Str.delete)
                            .font(AppTypography.labelMedium)
                            .foregroundColor(colors.onSurface)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(colors.outline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(customColors.taskCardBgColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = DefaultDataStoreRepository()
    let mgr = NotificationScheduleManager(store: store)
    let vm = NotificationsViewModel(scheduleManager: mgr)
    return NavigationStack {
        NotificationsScreen(viewModel: vm, navigateUp: {})
    }
    .environment(\.galleryColors, lightScheme)
    .environment(\.customColors, lightCustomColors)
}
#endif
