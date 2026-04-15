# Enzo iOS UX/UI Audit

Reviewed against iOS Human Interface Guidelines, SwiftUI best practices, and the `ios-ux-design` skill. All findings are observations only — no code was changed.

---

## Table of Contents

1. [Navigation & Information Architecture](#1-navigation--information-architecture)
2. [Touch Targets & Interaction](#2-touch-targets--interaction)
3. [Color System](#3-color-system)
4. [Typography](#4-typography)
5. [Charts & Data Visualization](#5-charts--data-visualization)
6. [Chat / ArcView](#6-chat--arcview)
7. [Onboarding Flow](#7-onboarding-flow)
8. [Segments & Goal Setting](#8-segments--goal-setting)
9. [Settings Sheet](#9-settings-sheet)
10. [Accessibility](#10-accessibility)
11. [Missing & Empty States](#11-missing--empty-states)
12. [Priority Summary](#12-priority-summary)

---

## 1. Navigation & Information Architecture

### Custom top-tab bar vs. native TabView

**What's there:** `MainTabView` renders a custom `HStack` of buttons with an animated underline indicator. The native `TabView` is intentionally not used.

**Issue:** The custom tab bar works, but it loses a lot for free: haptic feedback on tab switch, accessibility traits (the tab is not announced as a tab by VoiceOver), and standard iOS tab persistence behavior. For a 2-tab app this is low risk, but it also means the tabs don't get the system `.tabItem` treatment, so adding a third tab later requires refactoring the layout manually.

--> DO THIS:
 **Suggestion:** Consider using a native `TabView` with a hidden `.tabBar` using the `ZStack + opacity` pattern preserved for tab caching. This keeps the custom aesthetic while retaining system behaviors. Or, if the custom bar stays, add `.accessibilityAddTraits(.isSelected)` and `.accessibilityRole(.tab)` to each tab button.

---

### Navigation bar rebuilt manually, then hidden

**What's there:** `MainTabView` uses `NavigationStack` with `.toolbar(.hidden, for: .navigationBar)` and replaces the nav bar with a hand-rolled `topBar` HStack.

**Issue:** This is a common pattern and looks fine. The main gap is that the top bar has no large-title behavior — the title "Enzo" is always the same size regardless of scroll position. iOS users expect the title to compress as they scroll up. The current approach also means any sheet pushed from this view won't inherit a natural navigation context.

--> DO THIS:
**Suggestion:** The simplest fix is to restore the native nav bar and use `.navigationTitle("Enzo")` with a `trailing` toolbar item for the gear button. This gives the large-title-on-scroll pattern for free.

---

### Deep link / back navigation from SegmentDetailView

**What's there:** `SegmentDetailView` shows a `largeTitle`-size segment name at the top of the scroll content AND has the same name as the `.navigationTitle` (inline). When pushed, both are visible simultaneously — the user sees the segment name twice.

--> DO THIS:
**Suggestion:** Remove the explicit `.navigationTitle(segment.name)` in `SegmentDetailView` (or set it to a shorter version like "Segment") and rely on the large title in the scroll content as the primary heading. Alternatively, suppress the large-title body text when the nav bar inline title is visible.

---

## 2. Touch Targets & Interaction

The minimum recommended touch target on iOS is **44×44 pt**. Several elements fall short.

### Small touch targets identified

| Element | Location | Estimated size | Issue |
|---|---|---|---|
| Gear icon | `MainTabView.topBar` | ~30×30 pt | `.system(size: 20)` with 8pt vertical padding = ~36 pt |
| Refresh arrow | `ArcBriefingView` | ~20×20 pt | `.caption` font, no padding frame |
| Sort menu icon | `SegmentsView.sortBar` | ~28×44 pt | Width OK after HStack padding but visually tight |
| "Set a goal" link | `GoalHeaderView.emptyGoalState` | ~32×20 pt | `.caption` font, only 4pt top padding |
| Prompt chips | `PromptChipsView` | ~27 pt tall | `padding(.vertical, 7)` + caption font height ≈ 27 pt |
| Timeframe picker buttons | `FitnessChartView` | ~30 pt tall | `padding(.vertical, 6)` + caption font height ≈ 28 pt |

--> DO THIS:
**Suggestion:** Wrap icons in a `.frame(width: 44, height: 44)` `.contentShape(Rectangle())` modifier. For text-only buttons, add at least `padding(.vertical, 12)`.

---

### Segment rows use `.onTapGesture` instead of `Button`

**What's there:** In `GoalSettingView`, segment rows are built as plain `HStack` views with `.onTapGesture { selectSegment(segment) }`.

**Issues:**
- No visual press state — no highlight or opacity change on tap, which makes the app feel unresponsive.
- Not accessible via VoiceOver or Voice Control — tap gestures on non-interactive views are invisible to assistive technology.

--> DO THIS:
**Suggestion:** Wrap each row in a `Button` with `.buttonStyle(.plain)` to get system press feedback and accessibility for free.

---

### Pulsing "Strike now" animation

**What's there:** `SegmentStrikeRow` applies `.repeatForever` scale animation to the donut when `strikeLabel == "Strike now"`.

**Issue:** If many segments qualify as "Strike now", the list becomes visually noisy with multiple simultaneously pulsing elements. iOS HIG advises using motion purposefully and sparingly. Also, this animation does not respect `UIAccessibility.isReduceMotionEnabled`.

--> DO THIS:
**Suggestion:** Gate the animation on `!UIAccessibility.isReduceMotionEnabled`. Alternatively, replace the scale pulse with a static colored indicator (e.g., a colored dot or badge) since the color already communicates urgency.

---

## 3. Color System

### All colors are fixed hex — no semantic colors

**What's there:** `Color+Enzo.swift` defines all colors as `Color(hex: "...")`. Light mode is forced app-wide, so dark mode is not a practical concern today.

**Issue:** If dark mode support is ever added (or if Apple changes system rendering), all colors will need manual updates. More immediately: the hardcoded colors don't respond to increased contrast mode or other accessibility display preferences.

**Suggestion:** No immediate action needed given the intentional light-mode-only stance. But for the future, wrapping custom colors in `Color` asset catalog entries with Appearance variants would make this extensible without code changes.

--> DO THIS: Actually let's stop forcing light mode. We should support light and dark mode. And we should switch to semantic colors.

---

### Raw hex in `ArcMessageView`

**What's there:** User message bubbles use `Color(hex: "1C1C2E")` directly in the view file — a dark navy not present in the Enzo color system.

**Issue:** This breaks the design system contract. The color is not accessible via a named constant, so it can't be updated from one place, and it reads as an oversight rather than an intentional choice.

**Suggestion:** Add `Color.enzoUserBubble` to `Color+Enzo.swift` with value `1C1C2E` (or reconsider the color — a dark bubble on a `#FAFAFA` background is high-contrast, but the white text on that background should be verified for contrast ratio at the `.body` font size).

--> DO THIS: I think this issue will go away when we stop forcing light mode but we should check.

---

### "Disconnect" uses amber, not red

**What's there:** The "Disconnect Strava" row in `SettingsSheet` uses `Color.enzoAmber` for both the icon and label.

**Issue:** iOS convention is that destructive actions use red. Amber/yellow signals warning, not destruction. Disconnecting wipes all synced data — this warrants red and a confirmation alert, not just amber styling. A user who misreads amber as "caution" might not expect total data loss.

--> DO THIS: **Suggestion:** Use `.systemRed` (or a named `Color.enzoDestructive`) for the disconnect row. Add a `.confirmationDialog` before executing the disconnect.

--> DO THIS: Let's use semantic colors everywhere and use .systemRed here.

---

## 4. Typography

### Fixed-size font for small labels

**What's there:** Several small labels use `.system(size: N)` rather than a named text style:
- Segment score inside donut ring: `.system(size: 11, weight: .bold, design: .rounded)` — `SegmentStrikeRow`
- Gear icon: `.system(size: 20)` — `MainTabView`
- Star icon: `.font(.system(size: 10))` — `SegmentStrikeRow`, `SegmentDetailView`

**Issue:** Fixed sizes don't respond to Dynamic Type. Users with larger text preferences will see the donut score label at 11pt regardless of their system setting.

--> DO THIS: **Suggestion:** Use named text styles (e.g., `.caption2` for the small ring label) and let the system scale them. If the label needs to stay inside the ring geometry, use `.minimumScaleFactor(0.6)` instead of a fixed size.

---

### Unitless numbers inside donuts

**What's there:** Both `FitnessRingView` and `GoalHeaderView` display a raw integer (e.g., `72`) inside the donut ring with no unit or context label.

**Issue:** First-time users have no way to know what scale this number represents. Is it out of 100? Watts? Kilojoules? The "Fitness" / "Readiness" labels underneath identify *what* is shown, but not how to interpret the number. A user at "72" fitness and "65" readiness can't easily reason about the gap.

**Suggestion:** This is partly a design philosophy call. Options:
- Keep the number but add a brief tooltip or legend accessible via long press.
- Use the label instead of the number as the primary indicator (e.g., "Building" instead of "62").
- Show the number as `72 / 100` to make the scale explicit.

---

### Uppercase tracked labels are overused

**What's there:** Section headers like "Fitness", "Readiness", "Status", "Last ride", "Fitness history", "What to do next", "Readiness score" all use `.textCase(.uppercase)` with letter-spacing. This is used at least 12 times across views.

**Issue:** Uppercased labels are appropriate for section headers in a settings-style list, but using them for every label in a data-dense card layout adds visual weight and slows scanning. iOS HIG recommends using them only for group labels, not for inline data labels.

--> DO THIS: **Suggestion:** Reserve uppercase + tracking for true section headers (like the "Fitness history" card header or the Targets sort bar). Use regular (non-uppercase) caption styling for inline data labels like "Status", "Last ride", "Fitness", "Readiness".

---

## 5. Charts & Data Visualization

### Y-axis is hidden with no legend

**What's there:** `.chartYAxis(.hidden)` in `FitnessChartView`. The Y domain is dynamically calculated and varies by timeframe.

**Issue:** Users have no way to understand the absolute value shown at any point — they can see relative changes (up/down) but not magnitude. The "Your peak" and "Goal target" rule marks are helpful, but they only provide two anchors.

**Suggestion:** Show at minimum 2–3 Y-axis labels (e.g., floor, midpoint, peak) using `.chartYAxis { AxisMarks(preset: .aligned, position: .leading) }` with `.caption2` styling. This is tracked as a deferred item in CLAUDE.md — consider prioritizing it since it directly affects data comprehension.

---

### No discoverability signal for chart tap interaction

**What's there:** Tapping the chart selects the nearest snapshot and shows a `MonthDetailSheet`. There is no visual affordance indicating the chart is tappable.

**Issue:** This is a classic hidden gesture problem. Users who don't accidentally tap the chart will never discover month detail. A significant amount of development effort is invisible to most users.

**Suggestion:** Add a small "Tap for details" hint below the chart (`.caption2`, `.enzoSecondary`) that could fade out after the first tap interaction using `@AppStorage` to track whether it's been seen. Alternatively, show a subtle tap icon on initial appearance that fades after 2 seconds.

--> DO THIS: This is confusing. Just get rid of the tap action entirely. I didn't even know it was there.

---

### YTD + 1Y use the same axis stride

**What's there:** Both `ytd` and `oneYear` cases in the `xAxisMarks` builder use `.stride(by: .month, count: 1)` — every month labeled.

**Issue:** YTD in January has 0–1 data points; the chart will show a nearly empty area with a full row of month labels. In 1Y view, 12 month labels on a narrow chart is already known to cause overlap (noted in CLAUDE.md). Making them the same stride means the YTD view has proportionally more label density than chart content.

--> DO THIS: **Suggestion:** For `ytd`, reduce the stride or use abbreviated labels. A sensible approach: label only quarters (`.stride(by: .month, count: 3)`) for YTD and 1Y when the chart is narrow.

---

### MonthDetailSheet uses manual handle bar

**What's there:** `MonthDetailSheet` draws a manually-positioned `RoundedRectangle` at the top to simulate a drag handle.

**Issue:** The system provides `.presentationDragIndicator(.visible)` which renders an automatically positioned, properly accessible drag indicator. The custom one lacks the system's exact sizing, color token, and interaction semantics.

--> DO THIS: **Suggestion:** Replace the manual handle `RoundedRectangle` with `.presentationDragIndicator(.visible)` and remove the `.padding(.top, 12)` wrapper.

---

## 6. Chat / ArcView

### PromptChipsView is built but not used

**What's there:** `PromptChipsView` exists with two default chips ("What should I do this weekend?", "When was I last this fit?") but is not rendered in `ArcView`.

**Issue:** New users who see a blank message thread and an empty text field have no indication of what to ask or that asking is even the expected action. The chips were presumably built to solve this problem.

**Suggestion:** Show `PromptChipsView` above the input bar (or within the scroll content near the Enzo briefing) when `appState.arcMessages.isEmpty`. This guides first-time interaction and fills a blank state.

--> DO THIS: Delete this code. No prompt chips.

---

### Chat thread has no empty state

**What's there:** When `arcMessages` is empty and `isStreaming` is false, the scroll content shows only the chart, briefing, and then nothing. The input bar is present but unexplained.

**Issue:** Users don't know what the input bar is for until they use it. There's no label, subtitle, or prompt indicating "Chat with Enzo below."

--> DO THIS: **Suggestion:** Show a short contextual prompt above the input area when the thread is empty — e.g., "Ask Enzo about your training." This can be the placeholder text in the TextField (which currently says "Ask Enzo anything..." — this is good), but a visual hint above the bar would make the chat discovery more prominent.

---

### User message bubble uses an out-of-system color

As noted in the color section: `Color(hex: "1C1C2E")` in `ArcMessageView` breaks the design system. On the predominantly warm-neutral `#FAFAFA` background, a dark navy bubble looks more like a dark mode artifact than an intentional design choice.

**Suggestion:** Consider whether the contrast intent is right. A dark bubble on the light background is high-contrast, which is good for readability. If the dark navy is intentional, name it. If not, `Color.enzoPrimary.opacity(0.88)` with white text, or the Strava orange `Color.enzoAccent` with white text, would feel more on-brand.

--> DO THIS: No reason for this contrast. I think it was a hack to force light mode only and might go away when we stop forcing light mode. Delete this code.

---

### Scroll-to-bottom on streaming doesn't animate

**What's there:**
```swift
.onChange(of: appState.streamingText) {
    proxy.scrollTo("bottom")  // no withAnimation
}
```

The scroll-to-bottom on new messages uses `withAnimation`, but the real-time streaming scroll does not. This causes a visible jump every time a new token arrives.

--> DO THIS: **Suggestion:** Wrap the streaming scroll in `withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("bottom") }` to smooth the continuous scroll.

---

## 7. Onboarding Flow

### ConnectView uses hardcoded bottom padding

**What's there:** The bottom button padding is `padding(.bottom, 52)` — a magic number.

**Issue:** On iPhone models with a home indicator, the button may overlap or feel cramped. On smaller devices (SE), 52pt may be unnecessarily generous. The system-safe approach is to use `.safeAreaInset(edge: .bottom)` to attach the button to the bottom of the safe area.

--> DO THIS: **Suggestion:**
```swift
.safeAreaInset(edge: .bottom) {
    // button stack
    .padding(.horizontal, 32)
    .padding(.bottom, 16)
}
```

---

### SyncProgressView has no actual progress indicator

**What's there:** A timer cycles through 9 fake phase labels every 8 seconds. There's no spinner, no progress bar, and no connection to actual sync state beyond the phase text.

**Issue:** The UX presents what feels like deterministic, meaningful progress but is actually choreography. This is a well-known pattern (fake progress bars) but carries risk: if sync finishes in 4 seconds or takes 3 minutes, the phase labels cycle to arbitrary states. A user who sees "Enzo is almost ready..." for 2 minutes gets a confusing experience.

--> DO THIS: **Suggestion:** Add a `ProgressView()` (indeterminate spinner) centered on screen above the phase text. This honestly communicates "something is happening, we don't know exactly when it'll finish." The phase labels cycling below the spinner become flavor text, not false progress — which is more defensible UX.

---

### No privacy disclosure on ConnectView

**What's there:** The welcome copy from `Config.connectWelcomeText` is shown, then just a "Connect" button.

**Issue:** Strava OAuth grants access to the user's full activity history, heart rate data, and profile. iOS App Store guidelines and general trust-building best practices suggest disclosing what data will be accessed and why. This is particularly important for health/fitness data.

--> DO THIS: **Suggestion:** Add 1–2 lines below the welcome copy: e.g., "Enzo reads your ride history and heart rate to compute fitness trends. No data leaves your device." This is both good UX and sets expectations before the Strava permission screen appears.

---

## 8. Segments & Goal Setting

### Alternating row background in segment list

**What's there:** `SegmentsView` uses `index.isMultiple(of: 2)` to alternate between `.enzoCard` and `.enzoBg` row backgrounds.

**Issue:** Alternating row colors (zebrastriping) is a pattern from data tables, not native iOS lists. It adds visual noise without communicating any semantic difference between rows. iOS list rows are separated by dividers or whitespace, not alternating fills. The contrast between `#FAFAFA` and `#F7F7FA` is also extremely subtle (~3 hex difference) — barely perceptible and potentially causing confusion about why some rows look different.

--> DO THIS: **Suggestion:** Use a uniform row background. The separator tint (`enzoSecondary.opacity(0.15)`) already provides row division. Consider using `.listRowInsets` to add consistent padding instead.

---

### GoalSettingView `strikeLabelColor()` maps stale labels

**What's there:** Already flagged in CLAUDE.md. The function maps `"No brainer"` and `"Worth a shot"` but the current label set is `"Strike now"`, `"Almost there"`, `"Worth a shot"`, `"Getting there"`, `"Build first"`.

**Issue:** All 5-tier labels except `"Worth a shot"` fall through to `.enzoAmber`, so every label is amber in the goal-setting picker. This eliminates the color differentiation that helps users evaluate opportunities.

---

### Path B shows unsorted top segments

**What's there:** `pathBList` shows `appState.segments.prefix(3)` — the first 3 segments in the array's natural order (sync order).

**Issue:** The section header says "Top opportunities right now" — but without sorting by `strikeScore`, these are the first 3 segments found by Strava, not the 3 best opportunities. A user who chooses from Path B might pick a lower-readiness segment than they would from the main sorted list.

--> DO THIS: **Suggestion:** Use `appState.segments.sorted { $0.strikeScore > $1.strikeScore }.prefix(3)` to actually show the top 3 by strike score.

---

### Goal confirmation dismisses without undo

**What's there:** Tapping "Set this goal" in `SegmentDetailView` calls `appState.setGoal(...)` and then `dismiss()` immediately. There's no confirmation or undo.

**Issue:** Changing a goal discards the previous goal context and immediately triggers Enzo to regenerate briefings. While goals can be changed again from `SegmentDetailView`, there's no indication of this to the user post-confirmation.

--> DO THIS: **Suggestion:** This is low risk since goals can be changed freely. But adding a brief "Goal set: [name]" toast/banner notification after confirmation would close the feedback loop and reassure the user the action succeeded.

---

## 9. Settings Sheet

### "Reset sync history" has no confirmation

**What's there:** Tapping "Reset sync history" in `SettingsSheet` calls `appState.resetSyncHistory()` and `dismiss()` immediately.

**Issue:** This action deletes all `FitnessSnapshotModel` and `SegmentScoreModel` rows and immediately triggers a full re-sync. On a slow connection this could mean 5–10 minutes of lost data visibility. There's no "Are you sure?" guard.

--> DO THIS: **Suggestion:** Add a `.confirmationDialog` for this action: "This will delete your local fitness history and re-fetch everything from Strava. Continue?"

---

### Settings uses custom list-like layout instead of native List

**What's there:** `SettingsSheet` builds its rows with a custom `actionRow` builder inside a `VStack` with `Divider()` separators and `.background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))`.

**Issue:** This pattern requires manual management of dividers, backgrounds, and row styling. A native `List` with `.insetGrouped` style would provide these for free, adapt to accessibility changes, and look more at home in a settings context.

**Note:** The current implementation looks visually good — this is more of a maintainability concern than a visible UX issue.

---

### No sync status visible in main UI during manual sync

As noted in CLAUDE.md, triggering "Sync now" from Settings dismisses the sheet and starts a background sync with no visible indicator in the main UI. The user returns to the Today tab and has no feedback that anything is happening.

--> DO THIS: **Suggestion:** Show a subtle banner or progress indicator in `ArcView` or the top bar when `appState.isSyncing || appState.isSyncingPhase2` is true. A `.overlay` at the top of the content area with a small progress strip would be unintrusive.

---

## 10. Accessibility

### No accessibility labels on icon buttons

**What's there:** Interactive `Image(systemName:)` buttons have no `.accessibilityLabel()`:
- Gear icon in `MainTabView.topBar`
- Refresh arrow in `ArcBriefingView`
- Sort icon in `SegmentsView.sortBar`
- Send button in `ArcInputBar`

**Issue:** VoiceOver reads SF Symbol names as their symbol identifier, which is often non-descriptive. "arrow.clockwise" is announced as "arrow clockwise" not "Refresh Enzo's briefing."

**Suggestion:** Add `.accessibilityLabel("Settings")`, `.accessibilityLabel("Refresh briefing")`, `.accessibilityLabel("Sort segments")`, `.accessibilityLabel("Send message")` respectively.

---

### Donut charts have no accessibility description

**What's there:** The `Chart { SectorMark }` views in `FitnessRingView`, `SegmentStrikeRow`, and `GoalHeaderView` have `.chartLegend(.hidden)` and no `.accessibilityLabel` or `.accessibilityValue`.

**Issue:** VoiceOver users get no information from these charts. The numerical score and label nearby help, but the chart itself reads as an unnamed interactive element.

**Suggestion:** Add `.accessibilityLabel("Fitness score: \(Int(context.currentFitnessValue * 100)) out of 100, \(context.currentFitnessLabel)")` on the `Chart` views. For readiness donuts, include the strike label.

---

### Pulsing animation doesn't respect Reduce Motion

**What's there:** `SegmentStrikeRow` applies `.repeatForever` animation unconditionally when `strikeLabel == "Strike now"`.

**Issue:** Users who have enabled Reduce Motion (often for vestibular reasons) will still see continuous motion throughout the Targets tab.

--> DO THIS: **Suggestion:**
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
// ...
.animation(
    (segment.strikeLabel == "Strike now" && !reduceMotion)
        ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        : .default,
    value: isPulsing
)
```

---

### Trend arrows are Unicode characters

**What's there:** Trend direction is displayed as `↑`, `↓`, `→` in multiple views (`FitnessRingView`, `GoalHeaderView`, `SegmentStrikeRow`).

**Issue:** Unicode arrows are functional for VoiceOver (announced as "up arrow"), but SF Symbols (`arrow.up`, `arrow.down`, `arrow.forward`) would give more control over size, weight, and rendering, and integrate better with adjacent text styling.

**Suggestion:** This is a minor improvement. The Unicode approach works but `Image(systemName: "arrow.up").imageScale(.small)` inline with `Text` via a `ViewBuilder` or `Label` would be more consistent.

---

## 11. Missing & Empty States

### ArcView shows blank ring with no data

**Status:** Already flagged in CLAUDE.md as deferred.

--> DO THIS: **Suggestion when implemented:** The empty state should prompt action, not just explain absence. "Connect Strava to see your fitness history" with a button or a link back to settings is more useful than "No data yet." The empty ring could show a placeholder animation rather than a static gray arc.

---

### No feedback after "Set this goal"

The dismiss is immediate and silent. As noted in [Section 8](#8-segments--goal-setting), a brief confirmation notification would improve the feedback loop.

---

### SettingsSheet shows no "last synced" status by default

**What's there:** `syncStatusText` returns the last synced date only when `isSyncing` or `isSyncingPhase2` is true. In the `actionRow`, `sublabel` receives this value — but when not syncing, the condition evaluates to the `lastSyncedAt` format string.

Wait — re-reading the code: `syncStatusText` is passed as `sublabel` only when `appState.isSyncing || appState.isSyncingPhase2`. When both are false, `sublabel: nil` is passed. So the last synced date is never shown in the settings UI.

--> DO THIS: **Suggestion:** Always show the last synced timestamp as the sublabel when not actively syncing: `sublabel: appState.isSyncing ? syncStatusText : lastSyncedText`. Users frequently want to know if their data is current.

---

## Work Plan

All 27 annotated items extracted and grouped into phases. Phases are sequenced to minimize risk and dependency conflicts. Phase J (dark mode) is last because it cascades through every view and needs a design decision before implementation.

---

### Phase A — Safe Deletes
**Scope: S | Risk: Low | No dependencies**

Pure removals. Nothing new to design or think through.

| Task | File(s) |
|---|---|
| Remove chart tap overlay + `MonthDetailSheet` presentation (delete `MonthDetailSheet.swift`) | `FitnessChartView.swift`, `MonthDetailSheet.swift` |
| Delete `PromptChipsView.swift` | `PromptChipsView.swift` |

> **Note:** The `ArcMessageView` dark navy bubble (`1C1C2E`) will be addressed in Phase J when dark mode is designed. Don't touch it yet — the user's note says "I think it will go away when we stop forcing light mode."

---

### Phase B — Bug Fixes
**Scope: S | Risk: Low | No dependencies**

Single-line or near-single-line corrections.

| Task | File(s) |
|---|---|
| Path B: sort segments by `strikeScore` before `.prefix(3)` | `GoalSettingView.swift` |
| Streaming scroll: wrap `proxy.scrollTo("bottom")` in `withAnimation(.easeOut(duration: 0.1))` | `ArcView.swift` |
| Fix `strikeLabelColor()` stale label mapping (not annotated, but it's broken and trivial to fix — 5 lines) | `GoalSettingView.swift` |

---

### Phase C — Settings Polish
**Scope: S | Risk: Low | No dependencies**

All changes contained to `SettingsSheet.swift`.

| Task | Notes |
|---|---|
| Always show "last synced" sublabel on Sync row (not just when syncing) | Change the `sublabel:` condition |
| Add `.confirmationDialog` before "Reset sync history" executes | "This will delete your local history and re-fetch from Strava." |
| Change "Disconnect Strava" icon + label to `.systemRed` | Replace `Color.enzoAmber` with `Color(.systemRed)` |
| Add `.confirmationDialog` before disconnect executes | "This will remove all your data from this device." |

---

### Phase D — Touch Targets & Interaction
**Scope: M | Risk: Low–Medium | No dependencies**

Mechanical edits across several files. Each is isolated but there are many of them.

| Task | File(s) |
|---|---|
| Gear icon: add `.frame(width: 44, height: 44).contentShape(Rectangle())` | `EnzoAppApp.swift` (MainTabView) |
| Refresh arrow in briefing: add frame + contentShape | `ArcBriefingView.swift` |
| "Set a goal" link: increase to at least `padding(.vertical, 12)` | `GoalHeaderView.swift` |
| Timeframe picker buttons: increase vertical padding to 10pt | `FitnessChartView.swift` |
| Sort menu icon: ensure 44pt tappable area | `SegmentsView.swift` |
| GoalSettingView rows: convert `.onTapGesture` to `Button { } .buttonStyle(.plain)` | `GoalSettingView.swift` |
| Pulsing "Strike now" donut: gate on `@Environment(\.accessibilityReduceMotion)` | `SegmentsView.swift` |
| Remove alternating row backgrounds in segment list — use uniform background | `SegmentsView.swift` |

> **Note on Prompt chips:** PromptChipsView was deleted in Phase A, so no touch target fix needed there.

---

### Phase E — Navigation Refactor
**Scope: M | Risk: Medium | Test carefully after**

Structural change to the app's top-level chrome. Affects every screen. Test all navigation paths (tab switch, push to SegmentDetailView, settings sheet, goal setting sheet, back navigation) after making changes.

| Task | File(s) | Notes |
|---|---|---|
| Restore native nav bar in `MainTabView` — remove `toolbar(.hidden)`, move "Enzo" title to `.navigationTitle`, move gear button to `.toolbar` trailing item | `EnzoAppApp.swift` | The custom `topBar` HStack gets deleted |
| Add `.accessibilityAddTraits(.isSelected)` and appropriate role to custom tab buttons (if keeping custom bar, otherwise native TabView handles this) | `EnzoAppApp.swift` | Decide: keep custom underline tab bar but with native nav bar, or move to full native TabView |
| Fix `SegmentDetailView` double title — set `.navigationBarTitleDisplayMode(.inline)` with a short title or empty string; keep `largeTitle` text in scroll body | `SegmentDetailView.swift` | Currently shows segment name in both places |

---

### Phase F — Onboarding Polish
**Scope: S | Risk: Low | No dependencies**

All changes contained to onboarding screens.

| Task | File(s) |
|---|---|
| `ConnectView`: replace hardcoded `padding(.bottom, 52)` with `.safeAreaInset(edge: .bottom)` | `ConnectView.swift` |
| `SyncProgressView`: add `ProgressView()` spinner centered above the phase text | `SyncProgressView.swift` |
| `ConnectView`: add 1–2 lines of privacy disclosure copy below welcome text | `ConnectView.swift` + possibly `Config.swift` |

---

### Phase G — Chart & Main UI Polish
**Scope: M | Risk: Low–Medium**

| Task | File(s) | Notes |
|---|---|---|
| Fix YTD and 1Y x-axis: use quarterly stride (every 3 months) instead of monthly | `FitnessChartView.swift` | Addresses label overlap |
| Add sync-in-progress indicator in main UI when `isSyncing \|\| isSyncingPhase2` | `ArcView.swift` or `EnzoAppApp.swift` (MainTabView) | A slim banner or progress strip near the top bar |
| Add "Ask Enzo about your training." hint above input bar when `arcMessages.isEmpty` | `ArcView.swift` | Simple `Text` view shown conditionally |

---

### Phase H — Typography Polish
**Scope: M | Risk: Low | Many files touched**

These are mechanical but widespread. Do in a single pass to keep the diff readable.

| Task | File(s) |
|---|---|
| Replace `.system(size: 11)` in `SegmentStrikeRow` donut with `.caption2` + `.minimumScaleFactor(0.6)` | `SegmentsView.swift` |
| Replace `.system(size: 20)` on gear icon with `.title3` or `.body` | `EnzoAppApp.swift` |
| Replace `.system(size: 10)` star icons with `.caption2` | `SegmentsView.swift`, `SegmentDetailView.swift` |
| Reduce uppercase + tracking on inline data labels — "Status", "Last ride", "Fitness", "Readiness" should be plain `.caption` | `FitnessRingView.swift`, `GoalHeaderView.swift` |

---

### Phase I — Feedback & Empty States
**Scope: S–M | Risk: Low | No dependencies**

| Task | File(s) | Notes |
|---|---|---|
| Add "Goal set" confirmation banner/toast after `setGoal` action | `SegmentDetailView.swift`, `GoalSettingView.swift` | Needs a small reusable toast component or `.overlay` |
| `ArcView` empty state when `snapshots.isEmpty` | `ArcView.swift` | Deferred item from CLAUDE.md — show "Sync to see your fitness history" prompt |

---

### Phase J — Dark Mode + Semantic Colors
**Scope: L | Risk: High | Design decision required first**

This is the largest change and touches every view. **Do not start without answering the design questions below.**

#### Design questions to answer before coding:

| Token | Light value | Dark value (TBD) |
|---|---|---|
| `enzoBg` | `#FAFAFA` (near white) | ? (near black — `#1C1C1E`?) |
| `enzoCard` | `#F7F7FA` (slightly off-white) | ? (`#2C2C2E`?) |
| `enzoPrimary` | `#000000` | ? (`#FFFFFF`) |
| `enzoSecondary` | `#666666` | ? (`#AEAEB2`?) |
| `enzoAccent` | `#FC5201` (Strava orange) | Same? Slightly lighter? |
| `enzoGoal` | `#81C784` (green) | Same or adjusted? |
| `enzoAmber` | `#FFB74D` | Same or adjusted? |
| `enzoChartPrimary` | `#1E88E5` (blue) | Same or adjusted? |
| `enzoUserBubble` | `#1C1C2E` (dark navy) | Goes away — figure out a system-adaptive bubble color |

#### Implementation steps (after design is decided):

1. Replace `Color+Enzo.swift` hex definitions with `Color(uiColor: UIColor { ... })` adaptive variants (or move to Xcode Asset Catalog with Appearance variants)
2. Remove `.preferredColorScheme(.light)` from `WindowGroup` in `EnzoAppApp.swift`
3. Remove `.colorScheme(.light)` from `inputArea` in `ArcView.swift` (the `safeAreaInset` shadow hack)
4. Audit every view for hardcoded colors — grep for `Color(hex:` and `UIColor.white`/`.black` direct usage
5. Fix `ArcMessageView` user bubble — design the dark-mode-appropriate bubble color and name it `Color.enzoUserBubble`
6. Test all screens in both light and dark mode on multiple device sizes
7. Verify contrast ratios on colored text (accent on card, amber on bg, goal green on bg)

> **Note:** Phase J is intentionally last because (a) it cascades through every view, (b) it requires a design decision about the dark palette, and (c) completing Phases A–I first means there are fewer views to audit for dark mode compliance.

---

### Phase order summary

| Phase | Description | Scope | Can start immediately? |
|---|---|---|---|
| A | Safe deletes (chart tap, PromptChips) | S | Yes |
| B | Bug fixes (Path B sort, scroll animation) | S | Yes |
| C | Settings polish (confirmations, systemRed, last synced) | S | Yes |
| D | Touch targets & interaction | M | Yes |
| E | Navigation refactor | M | Yes — but test thoroughly |
| F | Onboarding polish | S | Yes |
| G | Chart & main UI polish | M | Yes |
| H | Typography polish | M | Yes |
| I | Feedback & empty states | M | Yes |
| J | Dark mode + semantic colors | L | **No — design decision needed first** |

Phases A, B, and C are fully independent and can be done in any order or combined into a single session. Phases D–I are also largely independent of each other. Phase J gates on design input.
