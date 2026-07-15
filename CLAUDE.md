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

### 2026-06-11

**`TradeSkillMaster_AuctionDB/TradeSkillMaster_AuctionDB.lua`**
- Removed the three AH Deposit lines (12h/24h/48h) — too cluttered now that relist scenario lines replace them.
- Removed `Total quantity: X units` line — redundant with the header's `X auctions / Y sellers` count.
- Expanded market tier from 3-tier to 5-tier: Scarce (< 50, green) / Low (< 200, cyan) / Medium (< 1,000, yellow) / High (< 5,000, orange) / Flooded (≥ 5,000, red). Same breakpoints drive the tier-aware `relistMultiplier` (0.95 / 0.90 / 0.85 / 0.70 / 0.55).
- Replaced old tier-specific SNIPE thresholds with a unified trigger: `netProfit > 0 AND roi > 25`, where `saleValue = floor(market × relistMultiplier × 0.95)`, `netProfit = saleValue − minBuyout − deposit48h`, `roi = netProfit / minBuyout × 100`.
- Added silent sale rate adjustment via `LibStub("AceAddon-3.0"):GetAddon("TSM_Accounting", true)`: if `saleRate ≥ 0.7` then `relistMultiplier += 0.08` (capped 0.95); if `saleRate < 0.3` then `relistMultiplier -= 0.10` (floor 0.30). Not shown in tooltip — only affects the internal relist target.
- Replaced old resell/vendor block with four relist scenario lines (50%, 65%, 80%, 95% of DBMarket). Each shows the target listing price in gray, net profit in green/red (after 5% AH fee and 48h deposit), and ROI%. `[!] SNIPE` header appears above these lines when the trigger fires; always shows relist lines when both prices are available.
- Added relist target price in parentheses on each label (e.g. `Relist 65% (4g 50s):`), so the listing price is visible at a glance without mental math.
- Fixed: `if #text > 0 then` wrapper block and `local lastScan = TSM:GetLastScanTime(itemID)` line were missing after a prior edit, causing the tooltip to return nothing. Re-inserted.

**TradeSkillMaster_AuctionDB/TradeSkillMaster_AuctionDB.lua** (continued 2026-06-11)
- Added `Sell (farm)` section below Vendor profit. Shows net gain over vendoring at 6 price targets: 50%, 65%, 80%, 95% of DBMarket, exact DBMarket, and DBMinBuyout. Formula: `sellNet = floor(price * 0.95) - deposit48h - vendorSellPrice`. Color: green if `sellNet > 0`, yellow if `>= -10c`, red if `< -10c`. Each label shows the target sell price in gray (e.g. `Sell 65% (4g 50s):`). Rendered inside the `if vendorSellPrice > 0` block so deposit and vendor baseline are always available.

### 2026-07-07

**`TradeSkillMaster_Auctioning/modules/ResetScan.lua`**
- Fixed `Reset:BuyAuction` and the Reset-tab cancel handler both registering `TSM_AH_EVENTS` with `Reset.RemoveCurrentAuction` (a function reference) instead of the string `"RemoveCurrentAuction"`. AceEvent calls function-reference message handlers with no `self` prepended, so `self` inside `RemoveCurrentAuction` was bound to the event name string, making `self:UnregisterMessage(...)` error out immediately and abort before the bought/canceled auction's row was ever removed from `scanData`/`auctionST`.
- **Why**: this was the root cause of "Auction not found. Skipped." repeating forever after a successful buyout in the Reset tab — the just-bought auction was never cleared from local state, so every subsequent buyout attempt re-validated against stale (already-sold) data and failed, requiring a full AH close/reopen to recover.

**`TradeSkillMaster_Auctioning/modules/ScanUtil.lua`**
- `Scan:ProcessItem` now always stores the scanned `auctionItem` in `Scan.auctionData[itemString]`, even when it has zero auction records.
- **Why**: previously an item was only stored when `#auctionItem.records > 0`. When posting an item with no competing auctions currently listed (common for niche/new items), `Scan.auctionData[itemString]` was never populated, so `GUI.lua`'s `UpdateAuctionsSTData` (`isCurrentItem` lookup) found nothing and the item's row vanished from the Manage tab mid-post even though posting was proceeding normally in the background.

**`TradeSkillMaster/Auction/AuctionQueryUtil.lua`**
- Removed the whole-item-class fallback query path (`GetCommonQueryInfoClass`, the `itemClasses` grouping, and the loop that added class-wide `name=""` queries to `combinedQueries`) from `GenerateQueriesThread`.
- **Why**: likely root cause of wow.exe hard-crashing (no Lua error) when scanning many items at once in Auctioning. When the query grouper estimated that searching an entire item class was cheaper (fewer pages) than searching per-item, it would issue a `name=""` query that pages through every auction of that whole class. On Ascension's high-volume/custom-item AH, this can pull thousands of distinct items with full auction records into `AuctionScanning.lua`'s `private.data` at once, which is enough to exceed the 32-bit client's memory ceiling and crash it outright rather than throw a catchable Lua error. Removing the fallback means more individual/small-group queries but bounds memory to the actual scanned item list.
- **Not yet confirmed**: no crash log/BugSack output was available to verify this was the exact trigger — user is testing in-game to confirm the crash is resolved.

### 2026-07-08

**`TradeSkillMaster_Shopping/modules/Util.lua`**
- Added `TSMAPI.AuctionScan:ClearCache()` to `private:PrepareForScan`, so the previous search's cached auction records are released the moment a new Shopping search starts.
- **Why**: `Util:StartFilterScan`/`StartItemScan` call `TSMAPI.AuctionScan:RunQuery(..., doCache=true)`, which stores every scanned record into `AuctionScanning.lua`'s module-level `scanCache` table (used for the "click a row to jump to its AH page" feature). That cache was previously only cleared in `Util:ShowSearchFrame`/`HideSearchFrame` (opening/closing the Shopping panel), NOT between individual searches. Doing several back-to-back single-item searches in the same session (reported: freeze then hard crash after ~4 searches) kept accumulating every prior search's full auction record set with nothing ever releasing it, growing memory until the 32-bit client choked — same failure class as the `AuctionQueryUtil.lua` whole-class-query crash fixed 2026-07-07. No crash log was available to confirm this was the exact trigger; user is testing in-game.
