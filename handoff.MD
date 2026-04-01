# Session Handoff — Enzo Voice / Prompt Tuning (next session)

## What was completed this session (Readiness Score Differentiation)

| Change | Files touched | Commit |
|---|---|---|
| SegmentScorer: replace trend modifier with PR age bonus + effort gap | `SegmentScorer.swift`, `SegmentScorerTests.swift` | 35e1e71 |
| SyncService: track latest effort per segment + demo score jitter | `SyncService.swift` | 99e4e7a |
| EnzoAppApp: force light mode at WindowGroup level | `EnzoAppApp.swift` | 2cbca98 |
| ArcView: force .colorScheme(.light) on inputArea (dark mode fix) | `ArcView.swift` | 7aff4d6 |
| SegmentsView: update readiness chip colors to 5-tier thresholds | `SegmentsView.swift` | 0d26506 |
| Enzo prompt: Italian coach character, updated labels, no markdown | `ClaudeService.swift`, `AppState.swift` | bf0c303 |
| enzo-voice.MD: sync with updated system prompt | `skills/enzo-voice.MD` | 4fe5816 |
| REVERTED: Enzo prompt changes (Chad found responses worse) | `ClaudeService.swift`, `AppState.swift`, `skills/enzo-voice.MD` | 4599be2, e72229b |

---

## Current app state

All changes committed and pushed. Working tree is clean. Branch: `main`.

**Important — Chad must re-sync to see updated scores:**
Settings → Reset sync history → Sync now

This rewrites `strikeScore` and `strikeLabel` in Supabase with the new formula (PR age bonus + effort gap modifier) and demo jitter.

---

## What the readiness score formula looks like now

```
score = clamp(0.75 + fitnessDelta + prAgeBonus + effortGapModifier, 0, 1)
```

- `fitnessDelta` = `currentFitnessValue − fitnessValueAtPR` (primary signal)
- `prAgeBonus` = `min(daysSincePR / 1095, 1.0) × 0.15` (linear, 0→+0.15 over 3 years)
- `effortGapModifier` = `clamp(−gapRatio × 0.5, −0.20, +0.10)` where `gapRatio = (lastEffortSeconds − prSeconds) / prSeconds`
- **Demo jitter**: `±0.25` deterministic noise seeded from `segId` — makes scores look meaningfully spread for demos. **Must be removed before shipping.**
- Trend modifier removed entirely (was ±0.05, global signal, same for all segments)

`lastEffortSeconds` is now correctly populated as the actual most recent elapsed time (previously always equalled `prSeconds`).

---

## Dark mode fix (complete)

App was rendering black text on dark backgrounds when the device was in dark mode. Fixed with:
1. `preferredColorScheme(.light)` on `WindowGroup` in `EnzoAppApp.swift`
2. `.colorScheme(.light)` directly on `inputArea` in `ArcView.swift` (safeAreaInset doesn't inherit window-level preference reliably)

---

## Enzo prompt: reverted

Attempted to add Italian coach character (piano piano, Dai, Coraggio etc.) and updated labels/no-markdown rules. Chad found the responses worse. Both commits were reverted cleanly. The system prompt is back to the pre-session state.

**Known issues still in system prompt (not fixed this session):**
- Readiness labels still say "No brainer, Worth a shot, Not quite ready" — stale (5-tier labels not reflected)
- Fitness labels in `enzo-voice.MD` system prompt section still say "Peak shape, Strong base, Building, Coming back" — stale

These should be fixed in the next prompt tuning session, carefully, with playground testing before touching the live app.

---

## Next session: Enzo Voice / Prompt Tuning

### The problem

The Enzo prompt is hard to tune directly in the app — there's no fast feedback loop. Responses take a full sync + app launch cycle to evaluate. The playground script (`scripts/enzo_playground.py`) exists for exactly this, but hasn't been used for tuning yet.

### Recommended approach

1. **Use the playground first.** Run `python3 scripts/enzo_playground.py --mode chat --message "What should I do this week?"` and iterate on the system prompt there. Fast feedback, no build required.
2. **Fix stale labels in system prompt.** Update readiness labels (5-tier) and fitness labels before any other tuning.
3. **Suppress markdown.** Add explicit no-markdown instruction. Test that it actually works in playground before committing.
4. **Italian character — optional.** Chad liked the idea but the implementation made responses worse. If retrying: use the playground to find the right balance before touching ClaudeService.swift.
5. **Lookahead prompt.** The improved version (goal-aware, direct address) was part of the reverted commit. Consider re-applying just the lookahead prompt change — it was directionally correct and simpler than the system prompt changes.

### Other things to look at this session

- **GoalSettingView.strikeLabelColor()** maps old 3-tier labels — falls through to amber for all new 5-tier labels. Simple fix.
- **Demo jitter in SyncService** — remove before any real user testing or App Store submission.
- **`enzo-voice.MD` stale labels** — fix alongside any prompt work.

### Working rules

- Read CLAUDE.md and handoff.MD before doing anything.
- Do NOT read scratch.md or UI-punch-list.md.
- Do not write a single line of code without presenting the plan and getting explicit approval from Chad.
- Make frequent, small commits — one change per commit, descriptive message.
- When Chad needs to test on device or perform a manual action (re-sync, playground run, etc.), stop and prompt him explicitly before continuing.

---

## Build notes from this session

**Demo jitter in SyncService — remove before shipping**
`SyncService.syncPhase2` applies a deterministic ±0.25 jitter to each segment's strike score, seeded from `segId` using a Knuth multiplicative hash. This makes scores look meaningfully spread during demos. The comment in code says "DEMO" and "Remove before shipping." Do not raise `phase2ActivityLimit` or run production syncs while this is active.

**latestEffortMap is populated correctly now**
Previously `lastEffortSeconds` always equalled `prSeconds` because it was only set inside the `prRank == 1` branch. Now a `latestEffortMap: [Int64: Int]` is populated on the first occurrence of each segment in the activity loop (activities are newest-first, so first = most recent). `lastEffortSeconds` in the PR row now uses `latestEffortMap[segId] ?? prSecs`.

**Prompt revert lesson**
Prompt changes are hard to evaluate without a fast feedback loop. Always use `scripts/enzo_playground.py` to test before touching `ClaudeService.swift` or `AppState.swift`. The playground streams responses in ~2 seconds — much faster than the app's cache + sync cycle.

**safeAreaInset dark mode**
`preferredColorScheme(.light)` on `WindowGroup` is not sufficient for `safeAreaInset` content — it needs an explicit `.colorScheme(.light)` on the view itself. Both are now in place.
