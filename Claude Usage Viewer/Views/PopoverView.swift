// PopoverView.swift
// Claude Usage Viewer

import AppKit
import SwiftUI

struct PopoverView: View {
    let store: UsageStore
    let openSettings: () -> Void

    private var fmt: TimeFormatting { TimeFormatting() }

    var body: some View {
        let now = store.now
        let limits = store.limits
        let projections = store.projections

        VStack(alignment: .leading, spacing: 14) {
            header(now: now)

            if limits.isEmpty {
                Text(store.visibleError?.message(now: now) ?? "Loading usage…")
                    .font(.callout)
                    .foregroundStyle(store.visibleError == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(limits) { limit in
                    LimitRowView(limit: limit, projection: projections[limit.kind],
                                 samples: store.history.samples(for: limit), now: now, fmt: fmt)
                }
            }

            if let snapshot = store.apiSnapshot {
                if !snapshot.weeklyBreakdown.isEmpty {
                    BreakdownView(rows: snapshot.weeklyBreakdown)
                }
                if let extra = snapshot.extraUsage {
                    ExtraUsageRow(extra: extra)
                }
            }

            if !limits.isEmpty, let err = store.visibleError {
                Label(err.message(now: now), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer(now: now)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Claude Usage").font(.headline)
            if let plan = store.planName {
                Text(plan)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if store.isFeedLive {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Live")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Updating live from Claude Code's status line")
            } else if let updated = store.lastUpdated {
                Text("Updated \(TimeFormatting.duration(now.timeIntervalSince(updated))) ago")
                    .font(.caption)
                    .foregroundStyle(store.isStale ? Color.orange : Color.secondary)
            }
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 14) {
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isLoading {
                    Text("Refreshing…")
                } else if let until = store.cooldownUntil {
                    Text("Refresh in \(TimeFormatting.duration(until.timeIntervalSince(now)))")
                } else {
                    Text("Refresh")
                }
            }
            .keyboardShortcut("r")
            .disabled(!store.canRefresh)
            .help(store.cooldownUntil != nil ? "Anthropic asked us to wait before checking again" : "Check usage now")

            Button("Usage page") { NSWorkspace.shared.open(Links.usagePage) }

            Spacer()

            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .keyboardShortcut(",")
                .help("Settings")
                .accessibilityLabel("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .keyboardShortcut("q")
                .help("Quit")
                .accessibilityLabel("Quit")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        HStack {
            Text("Extra usage this month").foregroundStyle(.secondary)
            Spacer()
            if let limit = extra.limit {
                Text("\(extra.used.formatted) of \(limit.formatted)").monospacedDigit()
            } else {
                Text(extra.used.formatted).monospacedDigit()
            }
        }
        .font(.caption)
    }
}
