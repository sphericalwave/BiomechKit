# BiomechKit

Training analysis shared by torque and suit. Foundation only; anatomy comes from
[AnatomyKit](https://github.com/sphericalwave/AnatomyKit).

## Soreness attribution

`SorenessAttribution.rank(note, sets:)` ranks the recent sets most likely to explain a
soreness note, each with a share and plain reasons:

```
Stability-ball hip bridge · 68%           (likely)
  – 22 h before: early in the usual soreness window
  – Gluteus Maximus: main mover
  – 3 sets, 45 reps, effort 8/10
  – First time in 23 days
  – Slow lowering: 4 s
Incline pigeon · 32%
  – 46 h before: the usual peak for soreness
  – …
```

Score per exercise and session:
`log(1 + Σ timing(Δt) × dose / 5) × muscle match × side × novelty × slow lowering`.

- **Timing:** a bell curve in log-hours peaking at 36 h, zero before 6 h and after 120 h.
- **Dose:** reps (or hold seconds / 3) × (effort/10)², × (1 + load/bodyweight).
- **Muscle match:** AnatomyKit soreness areas versus the muscles the exercise's movements
  load (main mover 1, assisting 0.5).
- **Novelty:** ×2 the first time, else 1 + (1 − e^(−gap/14 d)).
- **Possible strain:** flagged when discomfort ≥ 6 during a set comes less than 24 h
  before the note.

Design: `suitKit/SORENESS_ATTRIBUTION_PLAN.md`.

## Shared sets

`RecentSets` is the file torque writes to the `group.com.sphericalwave.fitwrench.suit` App Group
(`recent-sets.json`, last 8 days) and suit reads. On device only.

## Requirements

iOS 17+ / macOS 14+ / watchOS 10+, Swift 5.9+.
