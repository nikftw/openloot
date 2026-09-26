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

function Council:ReadMember(index)
	local name, rankName, rankIndex, _, _, _, _, officerNote, isOnline = GetGuildRosterInfo(index)
	if not name or not isOnline then
		return nil
	end
	return {
		name = name,
		rankName = rankName or "",
		rankIndex = rankIndex,
		officerNote = officerNote or "",
		council = self:Qualifies(rankIndex),
	}
end

function Council:EnsureSelf()
	if not IsInGuild() then
		return
	end
	local mine = OL:ShortName(OL:FullName("player"))
	local count = GetNumGuildMembers()
	for index = 1, count do
		local member = self:ReadMember(index)
		if member and OL:ShortName(member.name) == mine then
			self.byShort[mine] = member
			self:Changed()
			return
		end
	end
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
