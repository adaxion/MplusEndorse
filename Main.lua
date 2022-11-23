-- An addon to track +1/-1 endorsements for players you have grouped with in a M+
-- 
-- Author: Adaxion
-- Supported Game Version: 10.0.2
MplusEndorse = LibStub("AceAddon-3.0"):NewAddon(
    "M+ Endorse",
    "AceConsole-3.0"
)
local AceEvent = LibStub("AceEvent-3.0")
local AceComm = LibStub("AceComm-3.0")
local CommDistribution = {
    Party = "PARTY",
    Guild = "GUILD"
}

MplusEndorse.Version = "0.1.0"
MplusEndorse.CommPrefix = "MplusEndorse"
MplusEndorse.CommEvents = {
    InstanceReset = "MplusEndorse.InstanceReset",
    PlayerEndorsed = "MplusEndorse.PlayerEndorsed"
}

--- Return a set of normalized information about the current party
-- Will iterate over all of the party members expected in a M+ and return a rich set of information about that party member.
--
-- @return {{id = UnitGUID, name = string, realm = string, class = string, role = TANK|DAMAGER|HEALER|NONE, guild = string|nil}, ...}
local function getPartyMembers()
    local partyMembers = {}
    for i = 0, 4, 1 do
        local unit = "party" .. i
        local name, realm = UnitName(unit)
        if name then
            if realm == nil then
                realm = GetRealmName()
            end
            tinsert(partyMembers, {
                id = UnitGUID(unit),
                name = name,
                realm = realm,
                class = UnitClass(unit),
                role = UnitGroupRolesAssigned(unit),
                guild = GetGuildInfo(unit)
            })
        end
    end
    return partyMembers
end

--- Return a list of UnitGUID that you have partied with in M+
-- Please note that the list of returned UnitGUID will be across ALL characters for the account
--
-- @return {UnitGUID, ...}
function MplusEndorse:GetSeenPlayerIds()
    local keys = {}
    for key,_ in pairs(self.db.global.players) do
        tinsert(keys, key)
    end
    return keys
end

--- Return player information, including endorsement score, for the given UnitGUID.
-- If the userId provided has not been seen nil will be returned.
--
-- @param userId UnitGUID
-- @return {name = string, realm = string, numberOfEndorsements = int, score = int}|nil
function MplusEndorse:GetSeenPlayerInfo(userId)
    local player = self.db.global.players[userId]
    if player == nil then
        return nil
    end
    local score = 0
    local numEndorsements = 0

    if player.endorsements ~= nil then
        for mplusId, mplusInfo in pairs(player.endorsements) do
            numEndorsements = numEndorsements + 1
            score = score + mplusInfo["score"]
        end
    end

    return {
        name = player.name,
        realm = player.realm,
        numberOfEndorsements = numEndorsements,
        score = score
    }
end

--- Start tracking that a M+ run has started
-- When a M+ run is _finished_ there isn't enough information available to detail what level or dungeon or any other important info.
-- This method should be invoked when a M+ run has started, otherwise assertion errors will be thrown on an active keystone not found.
-- 
-- @return nil
function MplusEndorse:MythicPlusRunStarted()
    local partyMembers = getPartyMembers()
    local keystoneLevel, affixIds = C_ChallengeMode.GetActiveKeystoneInfo()
    local keystoneMapId = C_ChallengeMode.GetActiveChallengeMapID()
    local keystoneMapName = C_ChallengeMode.GetMapUIInfo(keystoneMapId)

    assert(keystoneLevel ~= nil, "Expected there to be an active keystone level but there is not one.")
    assert(keystoneMapId ~= nil, "Expected there to be an active keystone map ID but there is not one.")
    assert(keystoneMapName ~= nil, "Expected to retrieve a name for the keystone map ID but did not.")

    local affixes = {}
    local now = GetServerTime()
    for _, affixId in ipairs(affixIds) do
        local affixName = C_ChallengeMode.GetAffixInfo(affixId)
        tinsert(affixes, affixName)
    end

    local keystoneInfo = {
        id = now .. "-" .. keystoneLevel .. "-" .. keystoneMapId,
        level = keystoneLevel,
        mapId = keystoneMapId,
        name = keystoneMapName,
        startedAt = now,
        affixes = affixes
    }
    self.db.global.activeRun = {
        group = partyMembers,
        keystone = keystoneInfo
    }
end

function MplusEndorse:MythicPlusRunFinished()
    assert(self.db.global.activeRun ~= nil, "Expected to have tracked an active keystone but did not find one.")

    local keystone = self.db.global.activeRun.keystone
    local group = self.db.global.activeRun.group
    self.db.global.activeRun = nil
    self.db.global.runs[keystone.id] = {
        character = UnitName("player"),
        realm = GetRealmName(),
        guild = GetGuildInfo("player"),
        level = keystone.level,
        challengeMapId = keystone.mapId,
        affxies = keystone.affixes,
        startedAt = keystone.startedAt,
        finishedAt = GetServerTime(),
        group = group
    }

    MplusEndorseUI:ShowPartyEndorsement(getPartyMembers(), keystoneInfo)
end

function MplusEndorse:CheckActiveRunFailed()
    if self.db.global.activeRun ~= nil and C_ChallengeMode.IsChallengeModeActive() == false then
        self:MythicPlusRunFinished()
    end
end

function MplusEndorse:SeenPlayerInMythicPlus(runId, player)
    if self.db.global.players[player.id] == nil then
        self.db.global.players[player.id] = {
            name = player.name, 
            realm = player.realm,
            endorsements = {}
        }
    end
    assert(self.db.global.players[player.id] ~= nil, "Expected to have a data store for player ID " .. player.id .. " present but none was found")
    self.db.global.players[player.id]["endorsements"][runId] = {score = 0, note = ""}
end

function MplusEndorse:EndorsePlayerForMythicPlus(runId, player, score)
    self.db.global.players[player.id]["endorsements"][runId]["score"] = score
    local broadcastPayload = {
        type = self.Events.PlayerEndorsed,
        senderRunId = runId,
        player = player,
        score = score
    }
    AceComm:SendCommMessage(MplusEndorse.CommPrefix, LunaJson.encode(broadcastPayload), CommDistribution.Party)
end

function MplusEndorse:InitializeDatabase()
    self.db = LibStub("AceDB-3.0"):New("MplusEndorseDB")
    if self.db.global.runs == nil then
        self.db.global.runs = {}
    end
    if self.db.global.players == nil then
        self.db.global.players = {}
    end
    assert(self.db.global.runs ~= nil)
    assert(self.db.global.players ~= nil)
end

function MplusEndorse:OnInitialize()
    self:InitializeDatabase()
    self:RegisterChatCommand("mpe", "OnSlashCommand")

    AceEvent:RegisterMessage(MplusEndorseUI.OnPartyMemberAvailableForEndorsement, function(_, info)
        self:SeenPlayerInMythicPlus(info.run.id, info.member)
    end)

    AceEvent:RegisterMessage(MplusEndorseUI.OnPartyMemberEndorsed, function(_, info)
        self:EndorsePlayerForMythicPlus(info.run.id, info.member, info.score)
    end)

    AceEvent:RegisterEvent("CHALLENGE_MODE_START", function()
        self:MythicPlusRunStarted()
    end)

    AceEvent:RegisterEvent("CHALLENGE_MODE_COMPLETED", function(event, info)
        self:MythicPlusRunFinished()
    end)

    AceEvent:RegisterEvent("GROUP_LEFT", function(event, info)
        self:CheckActiveRunFailed()
    end)

    AceEvent:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
        local instanceResetSuccessRegex = string.gsub(INSTANCE_RESET_SUCCESS, "%%s", ".+")
        if string.match(msg, instanceResetSuccessRegex) then
            self:CheckActiveRunFailed()
            local instanceResetPayload = {type = MplusEndorse.CommEvents.InstanceReset}
            AceComm:SendCommMessage(MplusEndorse.CommPrefix, LunaJson.encode(instanceResetPayload), CommDistribution.Party)
        end
    end)

    AceComm:RegisterComm("MplusEndorse", function(event, json, distribution, sender)
        local payload = LunaJson.decode(json)
        if sender == UnitName("player") then
            return
        end

        if payload.type == MplusEndorse.CommEvents.InstanceReset then
            self:CheckActiveRunFailed()
        elseif payload.type == MplusEndorse.CommEvents.PlayerEndorsed then
            self:Print(sender .. " gave " .. payload.player.name .. " a " .. payload.score)
        end
    end)
end

function MplusEndorse:OnSlashCommand(subcommand)
    if subcommand == "" then
        MplusEndorseUI:ShowStatus(self.db.global.runs, self:GetSeenPlayerIds())
    else
        MplusEndorse:Print("Invalid command provided")
    end
end
