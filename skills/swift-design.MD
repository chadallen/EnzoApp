# Enzo SwiftUI Design Skill

Read this before building any view, component, or screen in Enzo.

---

## Aesthetic Direction

Confident, warm, editorial. A well-designed training journal — not a sports analytics dashboard. Dark mode first. Data supports narrative, not the other way around. Every screen should feel like it was designed specifically for this app, not generated from a SwiftUI template.

---

## Color Palette

Always use these exact values. Define them as extensions on `Color` in `Utils/Extensions/Color+Enzo.swift` and use the named versions throughout — never hardcode hex values in views.

```swift
extension Color {
    static let enzoBG = Color(hex: "#0A0A0F")          // Primary background
    static let enzoCard = Color(hex: "#141420")         // Card surfaces
    static let enzoAccent = Color(hex: "#4FC3F7")       // Electric blue — fitness curve, CTAs, Enzo voice border
    static let enzoGoal = Color(hex: "#81C784")         // Muted green — goal progress, positive deltas
    static let enzoAmber = Color(hex: "#FFB74D")        // Amber — "worth noting" signals only, used sparingly
    static let enzoTextPrimary = Color(hex: "#F0F0F5")  // Primary text
    static let enzoTextSecondary = Color(hex: "#8888AA") // Secondary text, timestamps, labels
}
```

**Color usage rules:**
- Blue (`enzoAccent`): fitness curve, primary CTAs, Enzo's voice left-border, active tab indicator
- Green (`enzoGoal`): goal progress bar fill, positive fitness delta arrows, "on track" signals
- Amber (`enzoAmber`): used sparingly — only when something genuinely warrants attention. Never for routine states.
- Never use red for inactivity, gaps, or missed rides. Amber is the most urgent signal in this app.
- White/light backgrounds: never. This is a dark mode app throughout.

---

## Typography

Use SF system fonts only. No custom fonts in MVP.

```swift
// Headers and section titles
.font(.system(.title2, design: .rounded, weight: .bold))

// Body text and Enzo responses  
.font(.system(.body, design: .default, weight: .regular))

// Data labels — times, scores, hours, numbers
.font(.system(.callout, design: .monospaced, weight: .medium))

// Secondary labels, timestamps
.font(.system(.caption, design: .default, weight: .regular))
.foregroundColor(.enzoTextSecondary)
```

**Typography rules:**
- SF Pro Rounded Bold for anything that orients the user (section headers, goal name, segment name)
- SF Pro Text Regular for anything Enzo says
- SF Pro Mono for all numbers — PRs in seconds/minutes, fitness scores, hours ridden
- Never mix rounded and default design in the same visual hierarchy level

---

## Layout & Spacing

```swift
// Standard card padding
.padding(16)

// Card corner radius
.cornerRadius(12)

// Section spacing in Arc scroll view
VStack(spacing: 20) { ... }

// Inner card spacing
VStack(alignment: .leading, spacing: 8) { ... }
```

**Layout rules:**
- Cards sit on `enzoCard` background with no border — depth comes from the background contrast, not strokes
- Generous padding inside cards — never cramped
- Section headers left-aligned, never centered
- Numbers right-aligned when paired with labels on the same row

---

## Key Components

### Enzo Voice Card (ArcBriefingView, LookaheadSuggestionView)
Any card showing Enzo's generated text gets a left border in `enzoAccent` to distinguish it visually:

```swift
.overlay(alignment: .leading) {
    Rectangle()
        .fill(Color.enzoAccent)
        .frame(width: 3)
        .cornerRadius(1.5)
}
.padding(.leading, 12) // indent content away from border
```

### Goal Progress Bar
Two labeled endpoints, filled to current position. Never red. Green fill up to current fitness, remaining in secondary color:

```swift
// Custom progress bar — do not use ProgressView
// Show: [Strong base ————●———— Peak shape needed]
// Left label: current fitness label
// Right label: required fitness label  
// Fill color: enzoGoal up to current position
// Empty color: enzoCard lightened slightly
```

### Strike Score Pills
Colored pill badges on segment rows:

```swift
// "Strike now" → enzoGoal background, dark text
// "Getting close" → enzoAmber background, dark text
// "Not yet" → enzoTextSecondary background, dark text
.padding(.horizontal, 8).padding(.vertical, 3)
.cornerRadius(10)
.font(.system(.caption, design: .rounded, weight: .semibold))
```

Only "Strike now" pills get a subtle pulse animation.

---

## Motion & Animation

**Chart draw-in:**
```swift
// Fitness curve draws left to right on appear
.trim(from: 0, to: animationProgress)
.onAppear {
    withAnimation(.easeOut(duration: 0.6)) {
        animationProgress = 1.0
    }
}
```

**Enzo text streaming:**
Stream character by character, not word by word. Characters feel alive; words feel mechanical.

**Section fade-in on Arc load:**
```swift
// Stagger each Arc section by 0.1s
.opacity(isVisible ? 1 : 0)
.onAppear {
    withAnimation(.easeIn(duration: 0.3).delay(Double(index) * 0.1)) {
        isVisible = true
    }
}
```

**Sheet presentations:** Use standard iOS spring. Never override sheet animation.

**What not to animate:**
- Tab switches — use standard UIKit crossfade
- List rows appearing — no animation
- Error states — no animation, just appear

**What never to build:**
- Confetti or celebration animations
- Streak counters or achievement badges
- Progress rings that spin on load (too gamified)

---

## Empty States

Every view that can be empty needs a designed empty state. Rules:
- Never show a blank white/dark screen
- Always include an Enzo line of copy in the empty state
- Use SF Symbols for illustration — no custom illustrations in MVP
- Empty state copy should be forward-looking, not apologetic

Example for Segments tab with no data:
```
[figure.cycling SF Symbol, large, enzoTextSecondary color]
"No segments yet"
"Enzo will find your best opportunities once your rides sync."
```

---

## What Not To Build

- Generic `NavigationView` with large title on every screen — use custom headers where the spec calls for them
- Default blue tint color — always override with `enzoAccent`
- `List` with default separators — use custom `VStack` + card layout
- `Toggle` or `Slider` controls styled with system defaults — match the dark palette
- Any shade of red in the UI