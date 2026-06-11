# TradeSkillMaster: Revived — Ascension Fork

A fork of **TradeSkillMaster Revived (Rev668)** for **World of Warcraft WotLK 3.3.0** on the [Ascension](https://www.ascension.gg/) classless private server.

The defining addition of this fork is **real-time price updates from individual Shopping searches** — no more waiting for a 20-minute full auction house scan to get current market values.

---

## What is TSM Revived?

TradeSkillMaster (TSM) is a suite of addons that automates gold-making in World of Warcraft: buying underpriced auctions, crafting items for profit, posting auctions in bulk, and tracking income. TSM Revived is a community-maintained port of TSM 2.8.3 to WotLK private servers.

This fork targets the **Ascension** server specifically, which runs a classless ruleset and may have custom item IDs not present in standard WotLK data.

### Addon modules included

| Module | Purpose |
|---|---|
| `TradeSkillMaster` | Core — APIs, group system, price sources, threading |
| `TradeSkillMaster_AuctionDB` | Price database — market values and min buyouts per item |
| `TradeSkillMaster_Shopping` | Auction search and sniper |
| `TradeSkillMaster_Auctioning` | Bulk auction posting |
| `TradeSkillMaster_Crafting` | Crafting queue and profit calculations |
| `TradeSkillMaster_Accounting` | Sales and expense tracking |
| `TradeSkillMaster_Mailing` | Automated mail collection |
| `TradeSkillMaster_ItemTracker` | Inventory tracking across characters |
| `TradeSkillMaster_Destroying` | Disenchanting / prospecting queue |
| `TradeSkillMaster_Warehousing` | Bank and guild bank management |

---

## Key Feature: Real-Time Price Updates from Shopping Searches

### The problem

In standard TSM Revived, `DBMarket` (market value) and `DBMinBuyout` are only updated by running a **Full Scan** of the entire auction house, which takes 20–60 minutes depending on server population. Until a full scan completes, Shopping's `% Market Value` column shows stale prices.

### The solution

This fork patches the Shopping module's search callback so that every individual item search — whether typed manually, triggered by a group search, or run by the Sniper — **immediately updates AuctionDB** with the results:

1. When a Shopping search returns results for an item, the raw auction records are captured before any display filtering.
2. The same percentile-based market value algorithm used by full scans runs on those records.
3. `DBMarket`, `DBMinBuyout`, and `lastScan` are updated in memory and persisted to `SavedVariables` immediately.
4. The `% Market Value` column in the Shopping results table reflects the freshly calculated price for that search.

**Result:** After searching for an item even once, its AuctionDB price is current. Over a normal play session of searching for deals, your entire price database stays warm without ever running a full scan.

### Design notes

- The market value calculation is identical to a full scan — same `CalculateMarketValue` percentile algorithm, same `scans[day]` running-average merge.
- Records are captured **before** the max-price display filter runs, so the price data includes the full market picture, not just the auctions below your shopping cap.
- The update path is guarded so it fails silently if AuctionDB is not loaded.
- Each search also records the **unique seller count** and **total quantity** seen, which are displayed in the item tooltip.

---

## Installation

### Requirements

- WoW client patched to **3.3.0** (WotLK)
- Connected to the **Ascension** server (or any WotLK 3.3.0 private server)

### Steps

1. **Download** this repository as a ZIP (`Code → Download ZIP`) or clone it:
   ```
   git clone https://github.com/your-username/tsm-ascension.git
   ```

2. **Copy all addon folders** into your WoW AddOns directory:
   ```
   WoW\Interface\AddOns\
   ```
   The folders to copy are:
   ```
   TradeSkillMaster\
   TradeSkillMaster_AuctionDB\
   TradeSkillMaster_Shopping\
   TradeSkillMaster_Auctioning\
   TradeSkillMaster_Crafting\
   TradeSkillMaster_Accounting\
   TradeSkillMaster_Mailing\
   TradeSkillMaster_ItemTracker\
   TradeSkillMaster_Destroying\
   TradeSkillMaster_Warehousing\
   ```

3. **Launch the game** and enable all TSM addons in the character select addon list.

4. In-game, open the auction house and the TSM panel will appear. Use `/tsm` to open the main configuration window.

### Updating

Pull the latest changes and re-copy the addon folders, then `/reload` in-game.

---

## Usage

### Getting started

- `/tsm` — opens the main TSM window (group management, settings, module configuration)
- `/reload` — reloads all addons after any file change

### Shopping and real-time prices

1. Open the Auction House. Click the **Shopping** tab in the TSM auction panel.
2. Type an item name (or paste a link) into the search box and press Enter or click **Search**.
3. Results appear with a `% Market Value` column. The first time you search an item, its `DBMarket` is calculated from those results and stored immediately.
4. Subsequent searches for the same item update the running average for today — repeated searches refine the value rather than overwriting it.

### Checking price freshness

Hover over any item with a TSM tooltip. The **TSM AuctionDB** section shows:

```
TSM AuctionDB:       12 auctions / 4 sellers (19hr ago)
  Market Value:      30s
  Min Buyout:        7s  (76% below market)
  Market tier:       Scarce
  [!] SNIPE - 76% below market  ROI 285%
  Relist 50% (15s):  6s 99c  (99% ROI)
  Relist 65% (19s):  10s 99c  (157% ROI)
  Relist 80% (24s):  15s 99c  (228% ROI)
  Relist 95% (28s):  20s 99c  (299% ROI)
  Vendor profit:     20s 93c
  Your crafting:     Cooking x1,2  |  Tailoring x4
  ――――――――――――――――
  ItemID: 12345
```

- **Header** — auction count, unique seller count, and time since last scan. Color-coded: green = under 3 hours, yellow = under 12 hours, red = older.
- **Min Buyout** — annotated with how far it sits below (green) or above (red) the 14-day market value.
- **Market tier** — 5-tier depth indicator: Scarce (< 50, green) / Low (< 200, cyan) / Medium (< 1,000, yellow) / High (< 5,000, orange) / Flooded (≥ 5,000, red). Drives the tier-aware relist multiplier used in all profit calculations.
- **SNIPE alert** — `[!] SNIPE - XX% below market  ROI YY%` appears when the net profit from relisting at the tier target exceeds 25% ROI. Relist multipliers by tier: 0.95 / 0.90 / 0.85 / 0.70 / 0.55 (Scarce → Flooded), silently adjusted ±0.08–0.10 by the item's historical sale rate from TSM Accounting if available.
- **Relist scenarios** — four lines showing profit and ROI for relisting at 50%, 65%, 80%, and 95% of market value. Each line shows the target listing price in gray (e.g. `Relist 65% (4g 50s):`), net profit in green/red (after 5% AH fee and 48h deposit), and ROI%. Always shown when both prices are available.
- **Vendor profit** — profit from vendoring the item instead of relisting. Shown below the relist scenarios.
- **Your crafting** — shown at the bottom of the AuctionDB section when `TSMAPI.GetReagentData` has data for the item. Lists each profession that uses the item as a reagent, with sorted/deduplicated quantities (e.g. `Cooking x1,2  |  Tailoring x4`). Populated by opening any trade-skill window; data persists across sessions. Only shown when the Crafting module is loaded.
- **ItemID** — always the very last line of the TSM tooltip block, separated by a gray rule. Useful for confirming item IDs on Ascension where custom items may share names with standard WotLK items.

### Price sources available

| Source key | Description |
|---|---|
| `DBMarket` | Weighted 14-day market value (updated by searches and full scans) |
| `DBMinBuyout` | Lowest buyout seen in the most recent search or scan for that item |

These can be used in any TSM price formula, e.g. `DBMarket * 0.8` as a maximum shopping price.

---

## SavedVariables

| File | Contents |
|---|---|
| `AscensionTSM_AuctionDB` | Per-item price database (market values, scan history) |
| `AscensionTSMDB` | Core TSM settings, groups, and operations |
| `AscensionTSM_ShoppingDB` | Saved searches and Shopping settings |

SavedVariables are stored in `WoW\WTF\Account\<account>\SavedVariables\`.

---

## Development

No build step — all code is Lua interpreted at runtime by the WoW client.

- **Test changes**: type `/reload` in-game
- **Debug output**: `print()` or `TSM:Print()` writes to the chat frame
- See `CLAUDE.md` for architecture details and a full changelog of modifications made to the upstream Rev668 codebase.

---

## Credits

- **Original TSM**: Sapu94, Bart39, and the TradeSkillMaster team
- **TSM Revived (Rev668)**: Gnomezilla (Warmane-Icecrown), BlueAo, andrew6180, Yoshiyuka, DimaSheiko, and contributors
- **This fork**: Real-time Shopping price update feature for Ascension
