-- ------------------------------------------------------------------------------ --
--                           TradeSkillMaster_AuctionDB                           --
--           http://www.curse.com/addons/wow/tradeskillmaster_auctiondb           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TSM_AuctionDB", "AceEvent-3.0", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0") -- load the AceGUI libraries

local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table

TSM.MAX_AVG_DAY = 1
local SECONDS_PER_DAY = 60 * 60 * 24

local savedDBDefaults = {
	realm = {
		appData = {},
		scanData = "",
		time = 0,
		lastCompleteScan = 0,
		lastScanSecondsPerPage = -1,
		appDataUpdate = 0,
	},
	profile = {
		tooltip = true,
		resultsPerPage = 50,
		resultsSortOrder = "ascending",
		resultsSortMethod = "name",
		hidePoorQualityItems = true,
		marketValueTooltip = true,
		minBuyoutTooltip = true,
		showAHTab = true,
		disableGetAll = false,
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("AscensionTSM_AuctionDB", savedDBDefaults, true)

	-- make easier references to all the modules
	for moduleName, module in pairs(TSM.modules) do
		TSM[moduleName] = module
	end

	-- register this module with TSM
	TSM:RegisterModule()
	TSM.db.realm.time = 10 -- because AceDB won't save if we don't do this...
	
	TSM.data = {}
	TSM:Deserialize(TSM.db.realm.scanData, TSM.data)
end

-- registers this module with TSM by first setting all fields and then calling TSMAPI:NewModule().
function TSM:RegisterModule()
	TSM.priceSources = {
		{ key = "DBMarket", label = L["AuctionDB - Market Value"], callback = "GetMarketValue" },
		{ key = "DBMinBuyout", label = L["AuctionDB - Minimum Buyout"], callback = "GetMinBuyout" },
	}
	TSM.icons = {
		{ side = "module", desc = "AuctionDB", slashCommand = "auctiondb", callback = "Config:Load", icon = "Interface\\Icons\\Inv_Misc_Platnumdisks" },
	}
	if TSM.db.profile.showAHTab then
		TSM.auctionTab = { callbackShow = "GUI:Show", callbackHide = "GUI:Hide" }
	end
	TSM.slashCommands = {
		{ key = "adbreset", label = L["Resets AuctionDB's scan data"], callback = "Reset" },
	}
	TSM.moduleAPIs = {
		{ key = "lastCompleteScan", callback = TSM.GetLastCompleteScan },
		{ key = "lastCompleteScanTime", callback = TSM.GetLastCompleteScanTime },
		{ key = "adbScans", callback = TSM.GetScans },
		--{ key = "adbOppositeFaction", callback = TSM.GetOppositeFactionData },
	}
	TSM.tooltipOptions = {callback = "Config:LoadTooltipOptions"}
	TSMAPI:NewModule(TSM)
end

function TSM:LoadAuctionData()
	local function LoadDataThread(self, itemIDs)
		-- process new items first
		for itemID in pairs(TSM.db.realm.appData) do
			if not TSM.data[itemID] then
				TSM:DecodeItemData(itemID)
				TSM:ProcessAppData(itemID)
				TSM:EncodeItemData(itemID)
			end
			self:Yield()
		end
		
		local currentDay = TSM.Data:GetDay()
		for _, itemID in ipairs(itemIDs) do
			TSM:DecodeItemData(itemID)
			TSM:ProcessAppData(itemID)
			if type(TSM.data[itemID].scans) == "table" then
				local temp = {}
				for i=0, 14 do
					if i <= TSM.MAX_AVG_DAY then
						temp[currentDay-i] = TSM.Data:ConvertScansToAvg(TSM.data[itemID].scans[currentDay-i])
					else
						local dayScans = TSM.data[itemID].scans[currentDay-i]
						if type(dayScans) == "table" then
							if dayScans.avg then
								temp[currentDay-i] = dayScans.avg
							else
								-- old method
								temp[currentDay-i] = TSM.Data:GetAverage(dayScans)
							end
						elseif type(dayScans) == "number" then
							temp[currentDay-i] = dayScans
						end
					end
				end
				TSM.data[itemID].scans = temp
			end
			TSM:EncodeItemData(itemID)
			self:Yield()
		end
	end
	
	local itemIDs = {}
	for itemID in pairs(TSM.data) do
		tinsert(itemIDs, itemID)
	end
	TSMAPI.Threading:Start(LoadDataThread, 0.1, nil, itemIDs)
end

function TSM:ProcessAppData(itemID)
	if not TSM.db.realm.appData[itemID] then return end
	
	TSM.data[itemID] = TSM.data[itemID] or {scans = {}, lastScan = 0}
	local dbData = TSM.data[itemID]
	local day = TSM.Data:GetDay()
	for _, appData in ipairs(TSM.db.realm.appData[itemID]) do
		local marketValue, minBuyout, scanTime = appData.m, appData.b, appData.t
		if abs(day - TSM.Data:GetDay(scanTime)) <= TSM.MAX_AVG_DAY then
			local dayScans = dbData.scans
			dayScans[day] = dayScans[day] or {avg=0, count=0}
			if type(dayScans[day]) == "number" then
				-- this should never happen...
				dayScans[day] = {dayScans[day]}
			end
			dayScans[day].avg = dayScans[day].avg or 0
			dayScans[day].count = dayScans[day].count or 0
			if #dayScans[day] > 0 then
				dayScans[day] = TSM.Data:ConvertScansToAvg(dayScans[day])
			end
			dayScans[day].avg = floor((dayScans[day].avg * dayScans[day].count + marketValue) / (dayScans[day].count + 1) + 0.5)
			dayScans[day].count = dayScans[day].count + 1
			if not dbData.lastScan or dbData.lastScan < scanTime then
				dbData.lastScan = scanTime
				dbData.minBuyout = minBuyout > 0 and minBuyout or nil
			end
		end
	end
	TSM.Data:UpdateMarketValue(dbData)
	TSM.db.realm.appData[itemID] = nil
end

function TSM:OnEnable()
	local function DecodeJSON(data)
		print(data)
		data = gsub(data, ":", "=")
		data = gsub(data, "\"horde\"", "horde")
		data = gsub(data, "\"alliance\"", "alliance")
		data = gsub(data, "\"m\"", "m")
		data = gsub(data, "\"n\"", "n")
		data = gsub(data, "\"b\"", "b")
		data = gsub(data, "\"([0-9]+)\"", "[%1]")
		loadstring("TSM_APP_DATA_TMP = " .. data .. "")()
		local val = TSM_APP_DATA_TMP
		TSM_APP_DATA_TMP = nil
		return val
	end

	if TSM.AppData then
		local realm = strlower(GetRealmName() or "")
		local faction = strlower(UnitFactionGroup("player") or "")
		if faction == "" or faction == "Neutral" then return end
		local numNewScans = 0
		local maxScanTime = 0
		for realmInfo, appScanData in pairs(TSM.AppData) do
			local r, f, t, extra = ("-"):split(realmInfo)
			if extra then
				r = r .. "-" .. f
				f = t
				t = extra
			end
			r = strlower(r)
			f = strlower(f)
			local scanTime = tonumber(t)
			if realm == r and (faction == f or f == "both") and scanTime > TSM.db.realm.appDataUpdate and abs(TSM.Data:GetDay() - TSM.Data:GetDay(scanTime)) <= TSM.MAX_AVG_DAY then
				local importData = DecodeJSON(appScanData)[faction]
				if importData then
					for itemID, data in pairs(importData) do
						itemID = tonumber(itemID)
						data.m = tonumber(data.m)
						data.b = tonumber(data.b)
						data.t = scanTime
						if itemID and data.m and data.b then
							TSM.db.realm.appData[itemID] = TSM.db.realm.appData[itemID] or {}
							tinsert(TSM.db.realm.appData[itemID], data)
						end
					end
					maxScanTime = max(maxScanTime, scanTime)
					numNewScans = numNewScans + 1
				end
			end
		end

		if numNewScans > 0 then
			TSM.db.realm.appDataUpdate = maxScanTime
			TSM.db.realm.lastCompleteScan = TSM.db.realm.appDataUpdate
			TSM:Printf(L["Imported %s scans worth of new auction data!"], numNewScans)
		end

		TSM.AppData = nil
	end

	TSM:LoadAuctionData()
end

function TSM:OnTSMDBShutdown()
	TSM.db.realm.time = 0
	TSM:Serialize(TSM.data)
end

function TSM:GetTooltip(itemString, quantity)
	if not TSM.db.profile.tooltip then return end
	if not strfind(itemString, "item:") then return end
	local itemID = TSMAPI:GetItemID(itemString)
	if not itemID or not TSM.data[itemID] then return end
	local text = {}
	local moneyCoinsTooltip = TSMAPI:GetMoneyCoinsTooltip()
	quantity = quantity or 1

	-- add market value info
	if TSM.db.profile.marketValueTooltip then
		local marketValue = TSM:GetMarketValue(itemID)
		if marketValue then
				if moneyCoinsTooltip then
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Market Value x%s:"], quantity), right = TSMAPI:FormatTextMoneyIcon(marketValue * quantity, "|cffffffff", true) })
					else
						tinsert(text, { left = "  " .. L["Market Value:"], right = TSMAPI:FormatTextMoneyIcon(marketValue, "|cffffffff", true) })
					end
				else
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Market Value x%s:"], quantity), right = TSMAPI:FormatTextMoney(marketValue * quantity, "|cffffffff", true) })
					else
						tinsert(text, { left = "  " .. L["Market Value:"], right = TSMAPI:FormatTextMoney(marketValue, "|cffffffff", true) })
					end
				end
			end
	end

	-- add min buyout info
	if TSM.db.profile.minBuyoutTooltip then
		local minBuyout = TSM:GetMinBuyout(itemID)
		if minBuyout then
			local marketValue = TSM:GetMarketValue(itemID)
			local pctStr = ""
			if marketValue and marketValue > 0 and minBuyout ~= marketValue then
				local pct = math.floor(math.abs(1 - minBuyout / marketValue) * 100)
				if minBuyout < marketValue then
					pctStr = " |cff00ff00(" .. pct .. "% below market)|r"
				else
					pctStr = " |cffff4444(" .. pct .. "% above market)|r"
				end
			end
			if quantity then
				if moneyCoinsTooltip then
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Min Buyout x%s:"], quantity), right = TSMAPI:FormatTextMoneyIcon(minBuyout * quantity, "|cffffffff", true) .. pctStr })
					else
						tinsert(text, { left = "  " .. L["Min Buyout:"], right = TSMAPI:FormatTextMoneyIcon(minBuyout, "|cffffffff", true) .. pctStr })
					end
				else
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Min Buyout x%s:"], quantity), right = TSMAPI:FormatTextMoney(minBuyout * quantity, "|cffffffff", true) .. pctStr })
					else
						tinsert(text, { left = "  " .. L["Min Buyout:"], right = TSMAPI:FormatTextMoney(minBuyout, "|cffffffff", true) .. pctStr })
					end
				end
			end
		end
	end

	-- add market tier
	local totalQty = TSM.data[itemID] and TSM.data[itemID].quantity or 0
	if totalQty > 0 then
		local tierLabel
		if totalQty < 50 then
			tierLabel = "|cff00ff00Scarce|r"
		elseif totalQty < 200 then
			tierLabel = "|cff00ffffLow|r"
		elseif totalQty < 1000 then
			tierLabel = "|cffffff00Medium|r"
		elseif totalQty < 5000 then
			tierLabel = "|cffff8800High|r"
		else
			tierLabel = "|cffff0000Flooded|r"
		end
		tinsert(text, { left = "  Market tier:", right = tierLabel })
	end


	-- add AH deposit and profit info
	local vendorSellPrice = select(11, TSMAPI:GetSafeItemInfo(itemString))
	if vendorSellPrice and vendorSellPrice > 0 then
		local marketValue = TSM:GetMarketValue(itemID)
		local minBuyout = TSM:GetMinBuyout(itemID)
		local deposit48h = max(1, floor(vendorSellPrice * 0.60))
		-- tier-aware relist target, adjusted by sale rate if available
		local qty = TSM.data[itemID] and TSM.data[itemID].quantity or 0
		local relistMultiplier
		if qty < 50 then relistMultiplier = 0.95
		elseif qty < 200 then relistMultiplier = 0.90
		elseif qty < 1000 then relistMultiplier = 0.85
		elseif qty < 5000 then relistMultiplier = 0.70
		else relistMultiplier = 0.55 end
		local acct = LibStub("AceAddon-3.0"):GetAddon("TSM_Accounting", true)
		if acct and acct.items and acct.items[itemString] then
			local _, totalSaleNum = acct:GetAvgSellPrice(itemString)
			local _, _, totalFailed = acct:GetAuctionStats(itemString)
			if totalSaleNum and totalSaleNum > 0 and totalFailed and totalFailed > 0 then
				local saleRate = totalSaleNum / (totalSaleNum + totalFailed)
				if saleRate >= 0.7 then relistMultiplier = math.min(relistMultiplier + 0.08, 0.95)
				elseif saleRate < 0.3 then relistMultiplier = math.max(relistMultiplier - 0.10, 0.30) end
			end
		end
		local saleValue = (marketValue and marketValue > 0) and floor(marketValue * relistMultiplier * 0.95) or nil
		if minBuyout and minBuyout > 0 and marketValue and marketValue > 0 then
			local netProfit = saleValue - minBuyout - deposit48h
			local roi = netProfit / minBuyout * 100
			if netProfit > 0 and roi > 25 then
				local belowPct = floor((1 - minBuyout / marketValue) * 100)
				tinsert(text, { left = "|cffff9900[!] SNIPE - " .. belowPct .. "% below market  ROI " .. floor(roi) .. "%|r", right = "" })
			end
			for _, pct in ipairs({50, 65, 80, 95}) do
				local relistPrice = floor(marketValue * (pct / 100))
				local relistSale = floor(relistPrice * 0.95)
				local profit = relistSale - minBuyout - deposit48h
				local roiPct = floor(profit / minBuyout * 100)
				local profitStr
				if profit >= 0 then
					profitStr = TSMAPI:FormatTextMoney(profit, "|cff00ff00", true) .. " |cff00ff00(" .. roiPct .. "% ROI)|r"
				else
					profitStr = "|cffff4444-" .. TSMAPI:FormatTextMoney(-profit, "|cffff4444", true) .. " (" .. roiPct .. "% ROI)|r"
				end
				tinsert(text, { left = "  Relist " .. pct .. "% (" .. TSMAPI:FormatTextMoney(relistPrice, "|cffaaaaaa", true) .. "):|r", right = profitStr })
			end
			local vendorProfit = vendorSellPrice - minBuyout
			if vendorProfit >= 0 then
				tinsert(text, { left = "  Vendor profit:", right = TSMAPI:FormatTextMoney(vendorProfit, "|cff999999", true) })
			else
				tinsert(text, { left = "  Vendor profit:", right = "|cffff4444loss|r" })
			end
		end
	end
	-- add heading and last scan time info
	if #text > 0 then
		local lastScan = TSM:GetLastScanTime(itemID)
		if lastScan then
			local timeColor = "|cffff0000"
			if (time() - lastScan) < 60 * 60 * 3 then
				timeColor = "|cff00ff00"
			elseif (time() - lastScan) < 60 * 60 * 12 then
				timeColor = "|cffffff00"
			end
			local timeDiff = SecondsToTime(time() - lastScan)		
			--tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = "|cffffffff" .. format(L["%s ago"], timeDiff) })
			tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = format("%s (%s)", format("|cffffffff".."%d auctions / %d sellers".."|r", TSM.data[itemID].quantity, TSM.data[itemID].sellerCount or 0), format(timeColor..L["%s ago"].."|r", timeDiff)) })
		else
			tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = "|cffffffff" .. L["Not Scanned"] })
		end
		return text
	end
end

function TSM:Reset()
	-- Popup Confirmation Window used in this module
	StaticPopupDialogs["TSMAuctionDBClearDataConfirm"] = StaticPopupDialogs["TSMAuctionDBClearDataConfirm"] or {
		text = L["Are you sure you want to clear your AuctionDB data?"],
		button1 = YES,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function()
			TSM.db.realm.lastCompleteScan = 0
			TSM.db.realm.appDataUpdate = 0
			for i in pairs(TSM.data) do
				TSM.data[i] = nil
			end
			TSM:Print(L["Reset Data"])
		end,
		OnCancel = false,
	}

	StaticPopup_Show("TSMAuctionDBClearDataConfirm")
	for i = 1, 10 do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.which == "TSMAuctionDBClearDataConfirm" then
			popup:SetFrameStrata("TOOLTIP")
			break
		end
	end
end

local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_="
local base = #alpha
local alphaTable = {}
local alphaTableLookup = {}
for i = 1, base do
	local char = strsub(alpha, i, i)
	tinsert(alphaTable, char)
	alphaTableLookup[char] = i
end

local function decode(h)
	if not h then return end
	if strfind(h, "~") then return end
	local result = 0

	local len = #h
	for j=len-1, 0, -1 do
		if not alphaTableLookup[strsub(h, len-j, len-j)] then error(h.." at index "..len-j) end
		result = result + (alphaTableLookup[strsub(h, len-j, len-j)] - 1) * (base ^ j)
		j = j - 1
	end

	return result
end

local function encode(d)
	d = tonumber(d)
	if not d or not (d < math.huge and d > 0) then -- this cannot be simplified since 0/0 is neither less than nor greater than any number
		return "~"
	end

	local r = d % base
	local diff = d - r
	if diff == 0 then
		return alphaTable[r + 1]
	else
		return encode(diff / base) .. alphaTable[r + 1]
	end
end

local function encodeScans(scans)
	local tbl, tbl2 = {}, {}
	for day, data in pairs(scans) do
		if type(data) == "table" and data.count and data.avg then
			-- New method of encoding scans.
			data = encode(data.avg).."@"..encode(data.count)
		elseif type(data) == "table" then
			-- Old method of encoding scans.
			for i = 1, #data do
				tbl2[i] = encode(data[i])
			end
			data = table.concat(tbl2, ";", 1, #data)
		else
			data = encode(data)
		end
		tinsert(tbl, encode(day) .. ":" .. data)
	end
	return table.concat(tbl, "!")
end

local function decodeScans(rope)
	if rope == "A" then return	end
	local scans = {}
	local days = {("!"):split(rope)}
	local currentDay = TSM.Data:GetDay()
	for _, data in ipairs(days) do
		local day, marketValueData = (":"):split(data)
		-- BUG FIXED: Guard against incorrectly encoded "day" or "marketValueData",
		-- which can happen extremely rarely due to some very rare, random bug
		-- somewhere else in TSM (or perhaps due to mixing different versions
		-- of TSM data). The cause of the rare corruption hasn't been found.
		-- NOTE: We simply skip any "days/market values" that cannot be decoded,
		-- which thereby ensures that we get a cleaned-up "decode" of the data,
		-- so that TSM will then write the fixed data when it next "re-encodes"
		-- the "decoded in-memory representation" of this item's data!
		if day ~= nil and day ~= "" and marketValueData ~= nil and marketValueData ~= "" then
			day = decode(day)
			-- BUG FIXED: Verify yet again that the day itself was properly decoded,
			-- but this time only check for "nil" which indicates "decode()" failure.
			if day ~= nil then
				-- Create a "scans" table entry for the decoded day.
				scans[day] = {}

				if strfind(marketValueData, "@") then
					-- New method of decoding scans.
					local avg, count = ("@"):split(marketValueData)
					avg = decode(avg)
					count = decode(count)
					if avg ~= "~" and count ~= "~" then
						if abs(currentDay - day) <= TSM.MAX_AVG_DAY then
							scans[day].avg = avg
							scans[day].count = count
						else
							scans[day] = avg
						end
					end
				else
					-- Old method of decoding scans.
					for _, value in ipairs({(";"):split(marketValueData)}) do
						local decodedValue = decode(value)
						if decodedValue ~= "~" then
							tinsert(scans[day], tonumber(decodedValue))
						end
					end
					if day ~= currentDay then
						scans[day] = TSM.Data:GetAverage(scans[day])
					end
				end
			end
		end
	end

	return scans
end

function TSM:Serialize()
	local results = {}
	for itemID, data in pairs(TSM.data) do
		if not data.encoded then
			-- should never get here, but just in-case
			TSM:EncodeItemData(itemID)
		end
		if data.encoded then
			tinsert(results, "?" .. encode(itemID) .. "," .. data.encoded)
		end
	end
	TSM.db.realm.scanData = table.concat(results)
end

function TSM:Deserialize(data, resultTbl, fullyDecode)
	if strsub(data, 1, 1) ~= "?" then return end

	for k, a, b, c, d, e, f in gmatch(data, "?([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^?]+)") do
		local itemID = decode(k)
		resultTbl[itemID] = {encoded=strjoin(",", a, b, c, d, e, f)}
		if fullyDecode then
			TSM:DecodeItemData(itemID, resultTbl)
		end
	end
end

function TSM:EncodeItemData(itemID, tbl)
	tbl = tbl or TSM.data
	local data = tbl[itemID]
	if data and data.marketValue then
		data.encoded = strjoin(",", encode(0), encode(data.marketValue), encode(data.lastScan), encode(0), encode(data.minBuyout), encodeScans(data.scans), encode(data.quantity))
	end
end

function TSM:DecodeItemData(itemID, tbl)
	tbl = tbl or TSM.data
	local data = tbl[itemID]
	if data and data.encoded and not data.marketValue then
		local a, b, c, d, e, f, g = (","):split(data.encoded)
		data.marketValue = decode(b)
		data.lastScan = decode(c)
		data.minBuyout = decode(e)
		data.scans = decodeScans(f)	
		data.quantity = decode(g)	
	end
end

function TSM:GetLastCompleteScan()
	local lastScan = {}
	for itemID, data in pairs(TSM.data) do
		TSM:DecodeItemData(itemID)
		if data.lastScan == TSM.db.realm.lastCompleteScan then
			lastScan[itemID] = { marketValue = data.marketValue, minBuyout = data.minBuyout }
		end
	end

	return lastScan
end

function TSM:GetLastCompleteScanTime()
	return TSM.db.realm.lastCompleteScan
end

function TSM:GetScans(link)
	if not link then return	end
	link = select(2, GetItemInfo(link))
	if not link then return	end
	local itemID = TSMAPI:GetItemID(link)
	if not TSM.data[itemID] then return	end
	TSM:DecodeItemData(itemID)

	return CopyTable(TSM.data[itemID].scans)
end

function TSM:GetOppositeFactionData()
	local realm = GetRealmName()
	local faction = "Ascension" -- UnitFactionGroup("player")
	if faction == "Horde" then
		faction = "Alliance"
	elseif faction == "Alliance" then
		faction = "Horde"
	else
		return
	end

	local data = TSM.db.sv.realm[faction .. " - " .. realm]
	if not data or type(data.scanData) ~= "string" then return end

	local result = {}
	TSM:Deserialize(data.scanData, result, true)
	return result
end

function TSM:GetMarketValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	if not TSM.data[itemID].marketValue or TSM.data[itemID].marketValue == 0 then
		TSM.data[itemID].marketValue = TSM.Data:GetMarketValue(TSM.data[itemID].scans)
	end
	return TSM.data[itemID].marketValue ~= 0 and TSM.data[itemID].marketValue or nil
end

function TSM:GetLastScanTime(itemID)
	TSM:DecodeItemData(itemID)
	return itemID and TSM.data[itemID].lastScan
end

function TSM:GetMinBuyout(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	return TSM.data[itemID].minBuyout
end