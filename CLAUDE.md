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
- `TSM.data[itemID]` — holds `{scans={}, lastScan=0, marketValue=X, minBuyout=Y, quantity=N, sellerCount=N}`
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
  → extract compact records + count unique sellers from auctionItem.records (before FilterRecords)
  → TSMAPI.AuctionDB.UpdateFromSearchResults(itemID, records, minBuyout, qty, sellerCount)
      → Data:CalculateMarketValue (same percentile algorithm as full scan)
      → merge into scans[today] running average
      → stores quantity, sellerCount on itemData
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

### 2026-06-06

**`TradeSkillMaster_AuctionDB/TradeSkillMaster_AuctionDB.lua`**
- Added AH deposit and profit lines to the AuctionDB tooltip section (shown below Min Buyout). Displays 12h/24h/48h deposit costs (15%/30%/60% of vendor sell price, min 1c) and estimated profit per duration. Profit uses `DBMinBuyout` as primary price source, falling back to `DBMarket`; shows N/A when both are unavailable.
- Extended Min Buyout tooltip line to append a percentage-below/above-market annotation in green (`% below market`) or red (`% above market`), calculated as `math.floor(math.abs(1 - minBuyout/marketValue) * 100)`. Only shown when both values are non-zero and unequal.
- Added "Total quantity: X units" line after Min Buyout, sourced from `TSM.data[itemID].quantity`.
- Updated tooltip header from `"X auctions (Y ago)"` to `"X auctions / Y sellers (Z ago)"` using `TSM.data[itemID].sellerCount`.
- **File write note**: the Edit tool does not persist writes to this file on this machine (likely blocked by AV/Defender). All changes must be applied via PowerShell `[System.IO.File]::WriteAllText`.

**`TradeSkillMaster_AuctionDB/Modules/data.lua`**
- Extended `Data:UpdateFromSearchResults` signature to accept `sellerCount` (5th parameter); stores it as `itemData.sellerCount = sellerCount or 0`.
- Updated `TSMAPI.AuctionDB.UpdateFromSearchResults` wrapper to pass `sellerCount` through.

**`TradeSkillMaster_Shopping/modules/Search.lua`**
- Extended the `ScanCallback` record loop to count unique sellers via `record.seller` (field confirmed in `LibAuctionScan-1.0/AuctionItem.lua`). Passes `sellerCount` as the 5th argument to `TSMAPI.AuctionDB.UpdateFromSearchResults`.

### 2026-06-07

**`TradeSkillMaster_AuctionDB/TradeSkillMaster_AuctionDB.lua`**
- Added "Market tier:" line immediately after "Total quantity:", colour-coded by quantity: Scarce (`< 50`, green), Medium (`< 500`, yellow), Saturated (`>= 500`, red).
- Replaced vendor/resell comparison block with a tier-aware SNIPE alert system. When `minBuyout` is far enough below `DBMarket` for the item's market depth tier (Scarce: `< 60% market` and `profitPct > 40`; Medium: `< 70%` and `> 25`; Saturated: `< 75%` and `> 15`), a highlighted `[!] SNIPE - XX% below market` header appears followed by Resell profit (with percentage) and Vendor profit. When no snipe is detected, the existing green/gray ranked comparison is shown instead.
- Fixed deposit profit formula throughout: profit is now `saleValue - minBuyout - deposit` where `saleValue = floor(DBMarket * 0.95)` (accounts for the 5% AH transaction fee applied to the sale). The old formula used raw `MinBuyout` as the sale reference.
- SNIPE/profit block now requires both `minBuyout > 0` and `marketValue > 0`; deposit profit lines show N/A when either is missing.

**`TradeSkillMaster/Core/Tooltips.lua`**
- Added ItemID line at the very bottom of the entire TSM tooltip, outside all module sections. Rendered directly in `private.LoadTooltip` after the module rendering loop, so it is always the absolute last visible line regardless of which modules are loaded.
- Format: gray `――――――――――――――――` separator line followed by `ItemID: XXXXX` in gray (`|cff999999`). ItemID extracted from `itemString` via `itemString:match("item:(%d+)")` with `tonumber(itemString)` numeric fallback.
- **Why**: Injecting from inside any module's `GetTooltip` would place the line within that module's block and subject it to module load-order. Placing it in `private.LoadTooltip` after the loop guarantees it is always last.
- **File write note**: also requires PowerShell `[System.IO.File]::WriteAllText` on this machine (same AV/Defender restriction as AuctionDB.lua).


**`TradeSkillMaster_Crafting/Modules/ReagentScan.lua`** (new file)
- Hooks `TRADE_SKILL_SHOW` and `TRADE_SKILL_UPDATE` events to scan all recipes in the open profession window using `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillNumReagents`, `GetTradeSkillReagentItemLink`, and `GetTradeSkillReagentInfo`.
- Builds a reverse lookup: `TSM.db.realm.reagentData[itemID][professionName] = {qty, ...}` (quantities sorted ascending, deduplicated) stored under `AscensionTSM_CraftingDB`.
- Exposes `TSMAPI.GetReagentData(itemID)` for read access from any module.
- Exposes `TSMAPI.MergeReagentData(itemID, profName, qty)` as a Phase 2 hook for external data sources (static tables, server feeds) to inject data without requiring an open trade-skill window.
- Mirrors live table to `TSMAPI.reagentData` after each scan.

**`TradeSkillMaster_Crafting/TradeSkillMaster_Crafting.lua`**
- Added `reagentData = {}` to the `realm` scope of `savedDBDefaults` so the table persists across sessions under `AscensionTSM_CraftingDB`.

**`TradeSkillMaster_Crafting/TradeSkillMaster_Crafting.toc`**
- Added `Modules\ReagentScan.lua` (loads after SpellNames2IDs.lua, before VellumInfo.lua).

**`TradeSkillMaster_AuctionDB/TradeSkillMaster_AuctionDB.lua`**
- Inside `GetTooltip`, after the AuctionDB header line is inserted, appends a `"Your crafting:"` line (gray label, white value) listing each profession and its sorted/deduplicated reagent quantities, e.g. `Cooking x1,2  |  Tailoring x4`. Professions are sorted alphabetically. The block is guarded by `if TSMAPI.GetReagentData then` so it fails silently if the Crafting module is absent.
