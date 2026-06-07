local TSM = select(2, ...)
local ReagentScan = TSM:NewModule("ReagentScan", "AceEvent-3.0")

local function insertDeduped(tbl, qty)
	for _, v in ipairs(tbl) do
		if v == qty then return end
	end
	tinsert(tbl, qty)
	table.sort(tbl)
end

function ReagentScan:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW", "ScanCurrentProfession")
	self:RegisterEvent("TRADE_SKILL_UPDATE", "ScanCurrentProfession")
end

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