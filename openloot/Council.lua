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

function Council:Qualifies(rankIndex)
	if rankIndex == nil then
		return false
	end
	if rankIndex == 0 then
		return true
	end
	return self:OfficerChat(rankIndex)
end

function Council:RankName(rankIndex, fallback)
	local order = type(rankIndex) == "number" and (rankIndex + 1) or nil
	if order and C_GuildInfo and C_GuildInfo.GuildControlGetRankName then
		local ok, name = pcall(C_GuildInfo.GuildControlGetRankName, order)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if order and GuildControlGetRankName then
		local ok, name = pcall(GuildControlGetRankName, order)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if type(fallback) == "string" and fallback ~= "" then
		return fallback
	end
	return ""
end

function Council:ReadMember(index)
	local name, rankName, rankIndex, officerNote, isOnline
	if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
		local ok, info = pcall(C_GuildInfo.GetGuildRosterInfo, index)
		if ok and type(info) == "table" then
			name = info.name
			rankName = info.rankName
			rankIndex = info.rank
			officerNote = info.officerNote
			if info.isOnline ~= nil then
				isOnline = info.isOnline
			else
				isOnline = info.online
			end
		end
	end
	if not name and GetGuildRosterInfo then
		name, rankName, rankIndex, _, _, _, _, officerNote, isOnline = GetGuildRosterInfo(index)
	elseif GetGuildRosterInfo and (type(officerNote) ~= "string" or officerNote == "") then
		local _, _, _, _, _, _, _, rosterNote = GetGuildRosterInfo(index)
		if type(rosterNote) == "string" and rosterNote ~= "" then
			officerNote = rosterNote
		end
	end
	if not name or not isOnline then
		return nil
	end
	if type(officerNote) ~= "string" then
		officerNote = ""
	end
	return {
		name = name,
		rankName = self:RankName(rankIndex, rankName),
		rankIndex = rankIndex,
		officerNote = officerNote,
		council = self:Qualifies(rankIndex),
	}
end

function Council:EnsureSelf()
	if not IsInGuild() or not GetGuildInfo then
		return
	end
	local _, rankName, rankIndex = GetGuildInfo("player")
	if type(rankIndex) ~= "number" then
		return
	end
	local name = OL:FullName("player")
	local short = OL:ShortName(name)
	self.byShort[short] = {
		name = name,
		rankName = self:RankName(rankIndex, rankName),
		rankIndex = rankIndex,
		officerNote = "",
		council = self:Qualifies(rankIndex),
	}
	self:Changed()
end

function Council:GroupedShort()
	local grouped = {}
	if not IsInGroup() then
		grouped[OL:ShortName(OL:FullName("player"))] = true
		return grouped
	end
	for index = 1, GetNumGroupMembers() do
		local name
		if IsInRaid() then
			name = GetRaidRosterInfo(index)
		else
			local unit = index == 1 and "player" or ("party" .. (index - 1))
			if UnitExists(unit) then
				name = OL:FullName(unit)
			end
		end
		if name then
			grouped[OL:ShortName(name)] = true
		end
	end
	return grouped
end

function Council:Rebuild()
	self.byShort = {}
	if not IsInGuild() then
		self:Changed()
		return
	end
	local grouped = self:GroupedShort()
	local count = GetNumGuildMembers()
	for index = 1, count do
		local member = self:ReadMember(index)
		if member then
			local short = OL:ShortName(member.name)
			if member.council or grouped[short] then
				self.byShort[short] = member
			end
		end
	end
	self:Changed()
end

function Council:Info(name)
	if not name then
		return nil
	end
	local short = OL:ShortName(name)
	if OL.devCouncil and OL.devCouncil[short] then
		return OL.devCouncil[short]
	end
	return self.byShort[short]
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
