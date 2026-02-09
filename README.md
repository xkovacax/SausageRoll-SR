# SausageRoll-SR - WoW 3.3.5a (Warmane)

## Features

### Import
- `/sr import` or Right-Click minimap — opens the import window
- Paste CSV from softres.it, click Import
- **Reimport** — open import anytime and paste new CSV (old data is automatically cleared)
- **Clear All SR** — deletes all reserves

### Main Window (`/sr`)
Split into two sections:

#### === SOFT RESERVE ===
- Shows only SR items that are in the **loot window** or in **bags**
- If a bag item disappears (trade/delete), it disappears from the window too
- Each item has: **Announce** (RW) | **Start Roll** | **Winner**
- SR roll — announces eligible players, only their rolls are counted

#### === MS ROLL ===
- Items from the **loot window** (uncommon+) that are NOT soft-reserved
- Items from **bags** that were looted in the current instance (2h trade window)
- Shows remaining trade time
- Each item has: **Announce** | **Start Roll** | **Winner**
- MS roll — all rolls are counted

### Announce
- Everything goes through **RAID_WARNING** (if you are RL/assist)
- Falls back to /raid if you don't have RW permissions

### Roll Tracking
1. Click **Start Roll** — announces in RW who should roll
2. Players roll `/roll`
3. Click **Winner** — evaluates the highest roll, announces the winner in RW

### Tooltip
- Hovering over an item shows SR info (cyan = in raid, red = not in raid)

## Commands
- `/sr` — main window (opens import if empty)
- `/sr import` — import CSV
- `/sr clear` — clear all
- `/sr check <name>` — check what a player has soft-reserved
- `/sr count` — statistics
- `/sr winner` — evaluate active roll

## Installation
1. Copy `SausageRoll-SR/` to `WoW/Interface/AddOns/`
2. `/reload`
