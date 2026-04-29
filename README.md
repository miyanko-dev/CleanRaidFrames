# Healer Raid Frames

Healer-focused indicators on Blizzard's raid and party frames. Only activates when the player is in a healer specialization (Preservation Evoker, Restoration Druid, Discipline/Holy Priest, Mistweaver Monk, Restoration Shaman, Holy Paladin).

## Features

- **Healer Buff Icons** (top-right, up to 2) — Spell icons for tracked HoTs and shields you cast on the unit, with a golden glow and a cooldown countdown. Tracked: Reversion, Lifebloom, Atonement, Soothing Mist, Renewing Mist, Enveloping Mist, Earth Shield, Beacon of Light, Beacon of Faith, Beacon of the Savior.
- **Crowd Control Icon** (bottom-left, single) — Shows the most relevant CC debuff with a countdown. Dispellable CC takes priority and gets a red glow.
- **Defensive Cooldown Icon** (top-left) — Shows a major defensive active on the unit with a green glow and a countdown. Uses Blizzard's `BIG_DEFENSIVE` filter with an added short-duration check to exclude long-term buffs.
- **Gradient Health Bars** — Subtle depth gradient overlay on raid health bars.

Indicators only attach to raid and party frames. Nameplates and arena enemy frames are excluded.
