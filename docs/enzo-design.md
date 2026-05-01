# Enzo Design Reference

The source of truth for visual design decisions in Enzo. Read this before building or modifying any view.

All color tokens live in `EnzoApp/Utils/Extensions/Color+Enzo.swift`. Never use raw hex values in views.

---

## Aesthetic Direction

Confident, warm, editorial — a well-designed training journal, not a sports analytics dashboard. Data supports narrative, not the other way around. Every screen should feel specific to this app, not generated from a SwiftUI template.

No streaks. No guilt. No missed-workout states. Amber is the most urgent signal this app ever sends.

---

## Color Tokens

### Adaptive (resolve at render time — light and dark mode)

| Token | Dark | Light | Use |
|---|---|---|---|
| `enzoBg` | `#1C1C1E` | `#FAFAFA` | Page/screen backgrounds |
| `enzoCard` | `#2C2C2E` | `#F7F7FA` | Card surfaces |
| `enzoPrimary` | `#FFFFFF` | `#000000` | Primary text |
| `enzoSecondary` | `#AEAEB2` | `#666666` | Secondary text, labels, timestamps |
| `enzoUserBubble` | `#3A3A52` | `#1C1C2E` | User chat bubbles — always a dark surface |

**`enzoUserBubble` rule:** This surface is always dark regardless of app appearance. Always pair it with `.white` text — never `Color.enzoPrimary`, which is white in dark mode but black in light mode.

### Fixed (identical in both modes)

| Token | Hex | Use |
|---|---|---|
| `enzoAccent` | `#FC5201` | Brand orange — primary CTAs, starred icons, active affordances |
| `enzoGoal` | `#81C784` | Positive signals, goal progress, "Strike now" tier |
| `enzoAmber` | `#FFB74D` | Attention-worthy states only — used sparingly |
| `enzoChartPrimary` | `#1E88E5` | Primary chart color, "Almost there" tier |
| `enzoChartSecondary` | `#90CAF9` | Secondary chart color |
| `enzoRingHigh` | `#27AE60` | Fitness ring — high end |
| `enzoRingLow` | `#E67E22` | Fitness ring — low end |

**Never use red.** Never use `.white` or `.black` directly in views. Always go through a token.

---

## Typography

SF system fonts only. Use the design/weight combos that appear in the codebase — don't introduce new ones.

| Role | Font spec | Example use |
|---|---|---|
| Section headers | `.caption` `.rounded` `.semibold` + `.uppercased()` + `.tracking(0.5)` | "STARRED SEGMENTS", tier labels |
| Hero names | `.title3` `.rounded` `.bold` | Segment name in HeroSegmentCard |
| Row names | `.body` `.rounded` `.semibold` | Segment name in SegmentStrikeRow |
| Subheadline / CTA labels | `.subheadline` `.rounded` `.semibold` | Button labels, hint card text |
| Secondary body | `.subheadline` `.rounded` (regular) | Supporting text, empty states |
| Data / times | `.caption` `.monospaced` | PR times, numeric stats |
| Score numbers (hero) | `.title3` `.monospaced` `.bold` | Donut center in detail view |
| Score numbers (compact) | `.caption2` `.rounded` `.bold` | Donut center in list rows |
| Captions / meta | `.caption` `.rounded` | Stat chips, distance, elevation |

---

## Layout & Spacing

```swift
// Standard card padding
.padding()  // 16pt all sides

// Card corner radius — full cards
.background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

// Inline hint / CTA cards
.padding(.horizontal, 12).padding(.vertical, 8)
RoundedRectangle(cornerRadius: 12)

// Section spacing in scroll views
VStack(alignment: .leading, spacing: 20)

// Inner card content
VStack(alignment: .leading, spacing: 8)  // or 14 for larger sections

// List row insets for card-style rows
EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

// List row insets for compact rows
EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16)
```

**List configuration:**
```swift
.listStyle(.plain)
.scrollContentBackground(.hidden)
.listRowBackground(Color.enzoBg)
.listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
```

Cards use no border — depth comes from background contrast, not strokes. Exception: bordered outline buttons use `Color.enzoSecondary.opacity(0.2)`.

---

## Navigation Structure

`NavigationStack` lives at the root (app entry point). `SegmentsView` is the single content view — it does not wrap itself in a stack.

```swift
// Typed navigation values — add cases here when adding new destinations
enum SegmentNavigation: Hashable {
    case detail(SegmentScore)
    case detailWithChat(SegmentScore)
}

// Declared in SegmentsView, works because it's inside the ancestor NavigationStack
.navigationDestination(for: SegmentNavigation.self) { nav in ... }
```

Supplementary flows (Find Segments, Settings) use `.sheet`. Sheets for focused tasks, navigation for drill-down.

---

## Key Components

### StrikeScoreDonut

Donut chart for strike score (0.0–1.0). Two sizes:
- **Compact** (`size ≤ 56`, default 44pt in list rows): shows score number only
- **Hero** (`size > 56`, 80pt in HeroSegmentCard, 120pt in SegmentDetailView): shows score + label

Tier color mapping (also used in `SegmentStrikeRow` trend arrows):
```swift
func strikeColor(for score: Double) -> Color {
    switch score {
    case 0.80...:       return .enzoGoal          // Strike now
    case 0.65..<0.80:   return .enzoChartPrimary   // Almost there
    case 0.45..<0.65:   return .enzoAmber          // Worth a shot
    default:            return .enzoSecondary      // Getting there / Build first
    }
}
```

"Strike now" pulses with `easeInOut(1.4s).repeatForever`. Always respect `.accessibilityReduceMotion`.

### HeroSegmentCard

Full-width card pinned above the segment list when a goal segment is set. Uses `enzoCard` background, 16pt corner radius, 14pt inner spacing. Contains goal badge, name + stat chips + donut (80pt), and two CTAs ("Ask Enzo" / "View details").

CTA style:
- Primary: `enzoAccent` text + `enzoAccent.opacity(0.08)` fill, 12pt corner radius
- Secondary: `enzoSecondary` text + `enzoSecondary.opacity(0.2)` stroke, no fill

### SegmentStrikeRow

List row with: name (+ star icon if starred/goal), PR time + trend arrow + distance + elevation, donut (44pt, compact). Trend arrow uses `enzoGoal` for up, `enzoSecondary` for flat/down. Vertical padding 6pt.

### Enzo Chat (ArcMessageView / ArcInputBar)

Enzo messages and user messages in `SegmentDetailView`. User bubbles use `enzoUserBubble` — always pair with `.white` text. Streaming is character-by-character into `@State var streamingText`.

### Section Headers

```swift
Text("SECTION TITLE")
    .font(.system(.caption, design: .rounded, weight: .semibold))
    .foregroundStyle(Color.enzoSecondary)
    .tracking(0.5)
```

Used in `List` section headers and as standalone labels above groups.

---

## Empty States

Every view that can be empty needs a designed state. Never show a blank screen.

```swift
VStack(spacing: 12) {
    Image(systemName: "star")          // SF Symbol, size 48, enzoSecondary
        .font(.system(size: 48))
        .foregroundStyle(Color.enzoSecondary)
    Text("Headline")                   // .headline .rounded .semibold, enzoPrimary
        .font(.system(.headline, design: .rounded, weight: .semibold))
        .foregroundStyle(Color.enzoPrimary)
        .padding(.top, 4)
    Text("Supporting copy.")           // .subheadline, enzoSecondary, centered
        .font(.system(.subheadline))
        .foregroundStyle(Color.enzoSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

Copy should be forward-looking and specific — not apologetic. See `skills/enzo-voice/skill.MD` for tone.

---

## Animation

- **StrikeScoreDonut pulse:** `easeInOut(duration: 1.4).repeatForever(autoreverses: true)` — "Strike now" only, gated on `!reduceMotion`
- **Loading phrases:** `easeInOut(duration: 0.4)` fade on 2-second timer
- **Streaming text:** character-by-character append into state; scroll-follows via `onChange(of: streamingText)`
- **Sheet presentations:** use standard iOS spring — never override

What not to animate: list rows appearing, error states, navigation transitions.  
What never to build: confetti, achievement badges, progress rings that spin on load.

---

## What Not To Build

- Raw hex colors in view files — always `Color.enzoXxx`
- `.white` or `.black` directly — use `enzoPrimary` (or `.white` only on `enzoUserBubble`)
- Red for any state — amber is the ceiling
- Streaks, missed-workout indicators, guilt-inducing states
- Custom `List` separators — use `.hidden` or `enzoSecondary.opacity(0.15)` tint
- Default blue system tint — always override with `enzoAccent`
