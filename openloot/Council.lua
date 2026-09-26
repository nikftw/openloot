local OL = OpenLoot

OL.Council = {}
local Council = OL.Council

local OFFICER_CHAT_SPEAK = 4

function Council:Init()
	self.byShort = {}
end

function Council:OfficerChat(rankIndex)
	if not C_GuildInfo or not C_GuildInfo.GuildControlGetRankFlags then
		return rankIndex <= 1
	end
	local ok, first, _, _, fourth = pcall(C_GuildInfo.GuildControlGetRankFlags, rankIndex)
	if not ok then
		return rankIndex <= 1
	end
	if type(first) == "table" then
		return first[OFFICER_CHAT_SPEAK] and true or false
	end
	return fourth and true or false
end

function Council:RankQualifies(rankIndex)
	if rankIndex == nil then
		return false
	end
	if rankIndex == 0 then
		return true
	end
	if OL.db.councilMode == "rank" then
		return rankIndex <= (OL.db.maxRankIndex or 1)
	end
	return self:OfficerChat(rankIndex)
end

function Council:Rebuild()
	self.byShort = {}
	if not IsInGuild() then
		self:Changed()
		return
	end
	local count = GetNumGuildMembers()
	for index = 1, count do
		local name, rankName, rankIndex, _, _, _, _, officerNote = GetGuildRosterInfo(index)
		if name then
			local short = OL:ShortName(name)
			self.byShort[short] = {
				name = name,
				rankName = rankName or "",
				rankIndex = rankIndex,
				officerNote = officerNote or "",
				council = self:RankQualifies(rankIndex),
			}
		end
	end
	self:Changed()
end

function Council:Info(name)
	if not name then
		return nil
	end
	return self.byShort[OL:ShortName(name)]
end

function Council:IsCouncilName(name)
	local info = self:Info(name)
	return info and info.council or false
end

function Council:IsLocalCouncil()
	return self:IsCouncilName(OL:FullName("player"))
end

function Council:Count()
	local count = 0
	for _, info in pairs(self.byShort) do
		if info.council then
			count = count + 1
		end
	end
	return count
end

function Council:Changed()
	if OL.Session and OL.Session:IsActive() and self:IsLocalCouncil() then
		OL.CouncilFrame:Show()
	end
	if OL.RaidMode then
		OL.RaidMode:ConsiderPrompt()
	end
end

function Council:PrintList()
	local names = {}
	for short, info in pairs(self.byShort) do
		if info.council then
			names[#names + 1] = short
		end
	end
	table.sort(names)
	if #names == 0 then
		OL:Print("No council members on the guild roster yet.")
		return
	end
	local mode = OL.db.councilMode == "rank" and ("rank 0-" .. tostring(OL.db.maxRankIndex or 1)) or "officer chat"
	OL:Print(string.format("Council (%s): %s", mode, table.concat(names, ", ")))
end

function Council:Slash(rest)
	local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" then
		self:PrintList()
	elseif sub == "rank" then
		local index = tonumber(arg)
		if not index or index < 0 then
			OL:Print("Usage: /openloot council rank <index>")
			return
		end
		OL.db.councilMode = "rank"
		OL.db.maxRankIndex = index
		self:Rebuild()
		OL:Print("Council is guild rank 0 through " .. index .. ".")
	elseif sub == "chat" then
		OL.db.councilMode = "officerChat"
		self:Rebuild()
		OL:Print("Council is anyone who can speak in officer chat.")
	else
		self:PrintList()
	end
end
