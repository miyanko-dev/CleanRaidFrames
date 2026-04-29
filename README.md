# Healer Raid Frames

Adds three icon overlays to Blizzard's raid and party frames so healers can see what matters at a glance. Active only in healer specs.

## Features

- **Healer Buff Display** (top-right corner) — Up to four of your own HoTs / shields / atonements on the unit. Per-spec buff list with drag-and-drop ordering, per-buff Show and Glow toggles, and a configurable section glow color.
- **Defensive Buff Icons** (top-left corner) — Major personal defensive cooldowns on the unit, with adjustable glow color and icon size.
- **Dispellable CC Debuff Icon** (bottom-left corner) — Any dispellable crowd-control effect on the unit. Higher priority than the generic dispellable debuff icon below.
- **Dispellable Debuff Icon** (bottom-left corner) — Any non-CC dispellable debuff on the unit. Hidden whenever a dispellable CC is active in the same slot.

## Configuration

Type `/hrf` to open the settings panel. Each section provides:

- Enable / Glow checkboxes
- Custom Color toggle (off = native gold proc glow, on = full color takeover via desaturation)
- Color picker
- Icon size as a percentage of raid-frame height
- Reset to defaults button
- Test mode (toggle from the panel) to preview icons on your raid frames

## Supported Healer Specs

Discipline / Holy Priest, Holy Paladin, Restoration Shaman, Mistweaver Monk, Restoration Druid, Preservation / Augmentation Evoker.
