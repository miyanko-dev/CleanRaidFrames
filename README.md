# CleanRaidFrames

Adds three icon overlays to Blizzard's raid and party frames so healers see what matters at a glance. Active in healer specs only.

## Features

| Overlay | Corner | Shows |
| --- | --- | --- |
| Healer buffs | Top-right | Up to four of your own HoTs, shields or atonements on the unit |
| Defensives | Top-left | The unit's major personal defensive cooldowns |
| Dispellable CC | Bottom-left | Any dispellable crowd-control effect, higher priority than the row below |
| Dispellable debuff | Bottom-left | Any non-CC dispellable debuff, hidden while a CC holds the slot |

- Per-spec buff list with drag-and-drop ordering and per-buff Show and Glow toggles
- Native gold proc glow, or a full color takeover with your own color per section
- Icon size set as a percentage of raid-frame height
- Test mode previews every icon on your live raid frames

## Installation

1. Copy the `CleanRaidFrames/` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **Clean Raid Frames** in the AddOns list.

## Configuration

Open **Options > AddOns > Clean Raid Frames**. Each section carries Enable and Glow checkboxes, a custom color toggle and picker, an icon size slider, test mode and a reset button.

## Supported specs

Discipline and Holy Priest, Holy Paladin, Restoration Shaman, Mistweaver Monk, Restoration Druid, Preservation and Augmentation Evoker.

## Requirements

World of Warcraft Retail (Interface `120005`).
