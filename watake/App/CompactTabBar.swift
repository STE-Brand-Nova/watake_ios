//
//  CompactTabBar.swift
//  watake
//

import DesignSystem
import SwiftUI

/// Custom bottom bar for compact width, replacing the native `TabView` tab
/// bar so Capture is a single control with distinct, prominent styling
/// (`WatakeFAB`) at its correct center position — instead of a duplicate
/// control floating above a plain tab item.
struct CompactTabBar: View {
    @Bindable var router: AppRouter

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(AppDestination.compactTabOrder) { destination in
                if destination == .capture {
                    captureItem(destination)
                } else {
                    plainItem(destination)
                }
            }
        }
        .padding(.top, WatakeSpacing.lg)
        .padding(.bottom, WatakeSpacing.xs)
        .background(WatakeColor.surface.raised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WatakeColor.border.subtle)
                .frame(height: 1)
        }
    }

    private func plainItem(_ destination: AppDestination) -> some View {
        let isSelected = router.selection == destination
        return Button {
            router.selection = destination
        } label: {
            VStack(spacing: WatakeSpacing.xxs) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 22))
                Text(destination.label)
                    .watakeType(.caption)
            }
            .foregroundStyle(isSelected ? WatakeColor.brand.primary : WatakeColor.text.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func captureItem(_ destination: AppDestination) -> some View {
        let isSelected = router.selection == destination
        return VStack(spacing: WatakeSpacing.xxs) {
            WatakeFAB(
                systemImage: destination.systemImage,
                accessibilityLabel: Text(destination.label)
            ) {
                router.selection = destination
            }
            .offset(y: -WatakeSpacing.xl)
            .padding(.bottom, -WatakeSpacing.xl)

            Text(destination.label)
                .watakeType(.caption)
                .foregroundStyle(isSelected ? WatakeColor.brand.primary : WatakeColor.text.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
