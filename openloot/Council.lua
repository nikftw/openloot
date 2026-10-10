local OL = OpenLoot

OL.Council = {}
local Council = OL.Council

local OFFICER_CHAT_SPEAK = 4
local RANK_READERS = { C_GuildInfo and C_GuildInfo.GuildControlGetRankName, GuildControlGetRankName }

function Council:Init()
	self.byShort = {}
end

function Council:RankName(rankIndex, fallback)
	local order = type(rankIndex) == "number" and (rankIndex + 1) or nil
	for _, reader in pairs(RANK_READERS) do
		if order and reader then
			local ok, name = pcall(reader, order)
			if ok and type(name) == "string" and name ~= "" then
				return name
			end
		end
	end
	return type(fallback) == "string" and fallback or ""
end

function Council:SeesOfficerChat(rankIndex)
	if type(rankIndex) ~= "number" then
		return false
	end
	if rankIndex == 0 then
		return true
	end
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

function Council:ReadMember(index, wanted)
	local name, rankName, rankIndex, _, _, _, _, officerNote, isOnline = GetGuildRosterInfo(index)
	if not name or not isOnline or not wanted[OL:ShortName(name)] then
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
		council = self:SeesOfficerChat(rankIndex),
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
		council = self:SeesOfficerChat(rankIndex),
	}
	self:Changed()
end

-- Rank and officer note for everyone in the group, from the guild roster.
-- Only the council window shows them, so a raider only keeps their own.
function Council:Rebuild()
	self.byShort = {}
	if not IsInGuild() then
		self:Changed()
		return
	end
	if not self:IsLocalCouncil() then
		self:EnsureSelf()
		return
	end
	local grouped = OL:Roster().byShort
	for index = 1, GetNumGuildMembers() do
		local member = self:ReadMember(index, grouped)
		if member then
			self.byShort[OL:ShortName(member.name)] = member
		end
	end
	self:Changed()
end

function Council:Info(name)
	if not name then
		return nil
	end
	local short = OL:ShortName(name)
	return self.byShort[short]
end

function Council:IsLocalCouncil()
	if not IsInRaid() then
		return false
	end
	local info = self.byShort[OL:Me()]
	if info then
		return info.council and true or false
	end
	if not IsInGuild() or not GetGuildInfo then
		return false
	end
	local _, _, rankIndex = GetGuildInfo("player")
	return self:SeesOfficerChat(rankIndex)
end

function Council:Changed()
	if OL.Session and OL.Session:IsActive() and self:IsLocalCouncil() then
		OL.CouncilFrame:Show()
	end
	if OL.RaidMode then
		OL.RaidMode:ConsiderPrompt()
	end
end
