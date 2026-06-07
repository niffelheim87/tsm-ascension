local TSM = select(2, ...)
local ReagentScan = TSM:NewModule("ReagentScan", "AceEvent-3.0")

local function insertDeduped(tbl, qty)
	for _, v in ipairs(tbl) do
		if v == qty then return end
	end
	tinsert(tbl, qty)
	table.sort(tbl)
end

-- Primary build path: derive reagentData from TSM's already-maintained crafts DB.
-- TSM.db.realm.crafts is populated by Util:ScanCurrentProfession() and persisted
-- across sessions, so this works even if no trade-skill window opens this session.
local function RebuildFromCraftsDB()
	if not TSM.db or not TSM.db.realm.crafts then return end
	local db = TSM.db.realm.reagentData
	wipe(db)
	for _, craft in pairs(TSM.db.realm.crafts) do
		local profName = craft.profession
		if profName and craft.mats then
			for matString, qty in pairs(craft.mats) do
				local itemID = tonumber(matString:match("item:(%d+)"))
				qty = tonumber(qty)
				if itemID and qty and qty > 0 then
					db[itemID] = db[itemID] or {}
					db[itemID][profName] = db[itemID][profName] or {}
					insertDeduped(db[itemID][profName], qty)
				end
			end
		end
	end
	TSMAPI.reagentData = db
end

function ReagentScan:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW", "ScanCurrentProfession")
	self:RegisterEvent("TRADE_SKILL_UPDATE", "ScanCurrentProfession")
	-- Build immediately from persisted crafts so tooltip shows data before any
	-- trade-skill window is opened this session.
	RebuildFromCraftsDB()
end

-- Supplementary live scan: captures a profession that is currently open in the
-- native trade-skill frame, including data TSM has not yet persisted to crafts.
function ReagentScan:ScanCurrentProfession()
	local profName = GetTradeSkillLine()
	if not profName or profName == "UNKNOWN" then return end

	local db = TSM.db.realm.reagentData
	local numSkills = GetNumTradeSkills()
	for i = 1, numSkills do
		local _, skillType = GetTradeSkillInfo(i)
		-- skillType is nil for craftable recipes; "header"/"subheader" for category rows
		if not skillType then
			local numReagents = GetTradeSkillNumReagents(i)
			for j = 1, numReagents do
				local link = GetTradeSkillReagentItemLink(i, j)
				if link then
					local itemID = tonumber(link:match("item:(%d+)"))
					if itemID then
						local _, _, qty = GetTradeSkillReagentInfo(i, j)
						qty = tonumber(qty)
						if qty and qty > 0 then
							db[itemID] = db[itemID] or {}
							db[itemID][profName] = db[itemID][profName] or {}
							insertDeduped(db[itemID][profName], qty)
						end
					end
				end
			end
		end
	end
	TSMAPI.reagentData = db
end

-- Read accessor used by other modules (e.g. AuctionDB tooltip).
TSMAPI.GetReagentData = function(itemID)
	if not TSM.db or not TSM.db.realm.reagentData then return nil end
	local data = TSM.db.realm.reagentData[itemID]
	if not data or not next(data) then return nil end
	return data
end

-- Phase 2 hook: external data sources inject reagent data without opening a
-- trade-skill window (e.g. static profession tables, server-side data feeds).
-- Note: data is cleared on each login by RebuildFromCraftsDB; Phase 2 callers
-- should merge their data after ADDON_LOADED or on demand.
TSMAPI.MergeReagentData = function(itemID, profName, qty)
	if not TSM.db or not TSM.db.realm.reagentData then return end
	qty = tonumber(qty)
	if not qty or qty <= 0 then return end
	local db = TSM.db.realm.reagentData
	db[itemID] = db[itemID] or {}
	db[itemID][profName] = db[itemID][profName] or {}
	insertDeduped(db[itemID][profName], qty)
	TSMAPI.reagentData = db
end