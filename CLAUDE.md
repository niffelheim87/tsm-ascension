# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TradeSkillMaster Revived (Rev668) — a suite of WoW AddOns for WotLK 3.3.0 on the Ascension classless private server. The primary goal is to modify **AuctionDB** so that individual **Shopping** searches update an item's market price (`DBMarket`/`DBMinBuyout`) and `lastScan` timestamp in real time, without requiring a full 20-minute auction house scan.

## Development Workflow

No build step. All code is Lua interpreted at runtime by the WoW client.

- **Test changes**: `/reload` in-game (reloads all AddOns and saved variables)
- **Debug output**: `print()` or `TSM:Print()` writes to the in-game chat frame
- **SavedVariables** persist across reloads in `C:\Ascension\Launcher\resources\ascension-live\WTF\`

Files in this directory are symlinked from the live AddOn folder:
`C:\Ascension\Launcher\resources\ascension-live\Interface\AddOns\`

## Architecture

### AddOn Suite

Each AddOn is a self-contained directory loaded by the WoW client. They share a common Ace3-based framework and communicate via the global `TSMAPI` table. Load order per AddOn is declared in its `.toc` file.

| AddOn | Role |
|---|---|
| `TradeSkillMaster/` | Core — APIs, group system, price sources, threading, auction layer |
| `TradeSkillMaster_AuctionDB/` | Price database — stores and calculates market values per item |
| `TradeSkillMaster_Shopping/` | Auction search UI and individual item searches |
| `TradeSkillMaster_Auctioning/` | Auction posting |
| `TradeSkillMaster_Crafting/` | Crafting queue |
| `TradeSkillMaster_Accounting/` | Sales/expense tracking |

### Key Files for the Main Goal

**AuctionDB price storage** (`TradeSkillMaster_AuctionDB/Modules/data.lua`):
- `TSM.data[itemID]` — holds `{scans={}, lastScan=0, marketValue=X, minBuyout=Y}`
- `TSM.data:SetData(itemID, minBuyout, quantity)` — records a new scan data point
- `TSM.data:UpdateMarketValue(itemID)` — recalculates `DBMarket` using a 14-day weighted average
- SavedVariable key: `AscensionTSM_AuctionDB`

**AuctionDB full scan** (`TradeSkillMaster_AuctionDB/Modules/Scanning.lua`):
- `Scanning:ProcessScanResults()` — processes a full scan page; calls `SetData` + `UpdateMarketValue` per item

**Shopping individual search** (`TradeSkillMaster_Shopping/modules/Search.lua`):
- `Search:StartFilterSearch(filter)` — initiates a targeted single-item search
- Result callback handlers — where individual auction results land and where AuctionDB update calls should be injected

**Core auction layer** (`TradeSkillMaster/Auction/AuctionScanning.lua`):
- Shared scan infrastructure (`RunScan`, `GetPageResults`) used by both full scans and Shopping searches

### Data Flow (implemented)

```
Shopping search result received
  → ScanCallback("process") in Search.lua
  → extract compact records from auctionItem.records (before FilterRecords)
  → TSMAPI.AuctionDB.UpdateFromSearchResults(itemID, records, minBuyout, qty)
      → Data:CalculateMarketValue (same percentile algorithm as full scan)
      → merge into scans[today] running average
      → Data:UpdateMarketValue → 14-day weighted DBMarket recalculated
      → TSM:EncodeItemData persists to SavedVariable
  → auctionItem:FilterRecords (maxPrice display filter, does not affect DB)
  → auctionItem:SetMarketValue (now reads freshly updated DBMarket)
```

## Coding Constraints

- **WotLK 3.3.0 Lua API only** — no APIs added in Cataclysm or later
- **Deliver complete modified files**, not snippets
- Ascension is a classless server and may have custom item IDs or mechanics not present in standard WotLK data

## Changelog

### 2026-06-05

**`TradeSkillMaster_AuctionDB/Modules/data.lua`**
- Added `Data:UpdateFromSearchResults(itemID, compactRecords, minBuyout, totalQuantity)` at end of file.
- Added `TSMAPI.AuctionDB.UpdateFromSearchResults` as the cross-addon callable wrapper.
- **Why**: AuctionDB had no API for updating a single item's price from outside. The new function reuses the existing `CalculateMarketValue` percentile algorithm and the same `scans[day]` running-average merge pattern used by `ProcessData`, so Shopping searches produce identical quality price data to full scans. Exposed via `TSMAPI` (the shared global namespace) so Shopping can call it without a hard load-order dependency.

**`TradeSkillMaster_Shopping/modules/Search.lua`**
- Modified `ScanCallback` (`"process"` event branch) to extract compact records from `auctionItem.records` and call `TSMAPI.AuctionDB.UpdateFromSearchResults` before `FilterRecords` and `SetMarketValue` run.
- **Why**: Records must be captured before `FilterRecords` removes auctions that exceed the user's max-price cap — those auctions are still valid market data. Running the DB update before `SetMarketValue` means the `% Market Value` column in Shopping's results table immediately reflects the freshly calculated price. The call is guarded by `if TSMAPI.AuctionDB and ...` so it fails safely if AuctionDB is absent.
