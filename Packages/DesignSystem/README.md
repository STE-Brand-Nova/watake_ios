# DesignSystem

The single source of visual truth for Watake. Every feature imports this package
and composes its tokens and primitives. **No feature re-implements colors,
spacing, typography, buttons, cards, chips, empty states, sections, or width
rules.** Values come from `Design.md`; width classes come from `RESPONSIVE.md`.

- SwiftUI only, iOS/iPadOS 17+.
- Zero dependencies. Never depends on WatakeDomain, WatakeStorage, a feature
  package, the app target, or SwiftData.

## Tokens

```swift
import DesignSystem

Text("Watake")
    .watakeType(.title1)                     // Dynamic Type–aware font
    .foregroundStyle(WatakeColor.text.primary)
    .padding(WatakeSpacing.md)               // 16pt
    .background(WatakeColor.surface.raised)
    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg))
```

- `WatakeColor` — `brand`, `surface`, `border`, `text`, `status`, `scrim`.
  All appearance-reactive (light/dark). Applied only to chrome, never to
  document/photo/watermark content.
- `WatakeSpacing` — `xxs`(4) `xs`(8) `sm`(12) `md`(16) `lg`(20) `xl`(24)
  `xxl`(32) `xxxl`(40) `xxxxl`(48) `huge`(64).
- `WatakeRadius` — `sm`(8) `md`(12) `lg`(16) `xl`(24) `pill`(999).
- `WatakeTypography` — `display, title1, title2, body, bodyEmphasis, caption,
  overline, mono`. Apply with `.watakeType(_:)`, which sets the Dynamic
  Type–scaled font, `Design.md` line height (as scaled `lineSpacing`), and
  overline case/tracking.

## Components

```swift
// Prefer WatakeButton: it disables itself while loading, so a slow save/export
// action cannot be double-fired.
WatakeButton("Save", variant: .primary, isLoading: isSaving) { save() }
WatakeButton("Delete", variant: .destructive) { delete() }

// The raw style is also available; it blocks taps while loading too.
Button("Save") {}.buttonStyle(.watake(.primary, loading: isSaving))

// Icon button requires an accessibility label; identifier is optional.
WatakeIconButton(
    systemImage: "trash",
    accessibilityLabel: Text("Delete"),
    accessibilityIdentifier: "library.folder.\(folder.id).delete"
) {}

WatakeCard { Text("Folder") }                      // .raised (default) or .sunken

// Tint colors the background/border only; the label uses text.primary so
// contrast stays ≥ 4.5:1 for any tint.
WatakeTagChip("Draft", color: WatakeColor.status.warning)

WatakeSection("Recent", actionTitle: "See all") { action } content: { … }

WatakeEmptyState(
    systemImage: "tray",
    title: "No documents",
    message: "Scanned documents appear here.",
    actionTitle: "Scan",
    action: { … }
)

TextField("Search", text: $query).textFieldStyle(.watakeSearch)
WatakeInspectorSection("Advanced", isExpanded: $expanded) { … }
```

## Adaptive width

```swift
GeometryReader { proxy in
    let widthClass = WatakeLayout.widthClass(for: proxy.size.width)
    let gutter = WatakeLayout.gutter(for: widthClass)
    let columns = WatakeLayout.columnCount(for: widthClass)
    …
}
```

- `compact < 700`, `regular 700...1099`, `expanded >= 1100` — classify the
  **container width**, never the device or `UIScreen.main.bounds`.
- Helpers return gutters and column counts only. Features build their own layout
  with `GeometryReader`, `ViewThatFits`, adaptive grids, and
  `NavigationSplitView`. This package ships no navigation shell.

## Use this / do not do this

- ✅ `WatakeColor.brand.primary` — ❌ `Color(red:…)`, raw hex, `Color.blue` as theme.
- ✅ `WatakeSpacing.md` — ❌ `.padding(16)` magic numbers.
- ✅ `.watakeType(.body)` — ❌ `.font(.system(size: 16))`.
- ✅ `WatakeButton(…, isLoading:)` — ❌ a loading button that still accepts taps.
- ✅ tint chip background/border, label stays `text.primary` — ❌ tint as the
  label color (can fail 4.5:1).
- ✅ pass a unique `accessibilityIdentifier` per instance — ❌ rely on a shared
  DesignSystem constant on every control.
- ✅ `WatakeLayout.widthClass(for:)` — ❌ branching on `UIDevice`/idiom.
- ✅ document/photo/watermark colors owned by the feature — ❌ routed through
  theme tokens or inverted for Dark mode.

## Adding a component — prove two consumers first

Do **not** add a primitive speculatively. Add one only after **two real feature
usages** need the same behavior. Feature-specific visuals compose existing
primitives until then. New primitives keep the accessibility guarantees below.

## Accessibility checklist

- [ ] Interactive targets ≥ 44×44pt.
- [ ] Icon-only controls have an accessibility label (`WatakeIconButton`
      enforces this).
- [ ] Text uses `.watakeType(_:)` so it scales with Dynamic Type; layouts reflow
      / wrap, no clipping.
- [ ] Body text contrast ≥ 4.5:1 (tint chips only the background/border; label
      stays `text.primary`, verified by `ContrastTests`).
- [ ] Motion respects Reduce Motion (button press animation already does).
- [ ] Loading buttons block interaction (`WatakeButton` / the style enforce it).
- [ ] Correct in both Light and Dark; geometry identical across appearances.
- [ ] Controls that tests target get a unique `accessibilityIdentifier` from the
      caller via `watakeAccessibilityIdentifier(_:)`.
