-- An addon to track +1/-1 endorsements for players you have grouped with in a M+
-- 
-- This module is responsible for the primary domain logic of the addon and gluing our components into Ace and 
-- Blizzard's API appropriately.
-- 
-- ## StartTypes
-- 
-- UnitGUID = UnitGUID(unit)
-- PartyMember = {id = UnitGUID, name = string, realm = string, class = string, role = TANK|DAMAGER|HEALER|NONE, guild = string|nil}
-- 
-- ## EndTypes
-- 
-- Author: Adaxion
-- Supported Game Version: 10.0.2
local AceEvent = LibStub("AceEvent-3.0")
local AceComm = LibStub("AceComm-3.0")
local CommDistribution = {
    Party = "PARTY",
    Guild = "GUILD"
}
local MplusEndorse = LibStub("AceAddon-3.0"):NewAddon(
    "M+ Endorse",
    "AceConsole-3.0"
)

MplusEndorse.Version = "0.1.0"

--- Hook for Ace3 to allow addon to initialize itself UI load.
--
-- This hook ensures our "db" is setup properly, we're registered to respond to all appropriate events, and gives
-- our UI initializer a chance to take care of whatever initialization procedures are necessary.
--
-- @return void
function MplusEndorse:OnInitialize()
    self:InitializeDatabase()
    self:RegisterBlizzardEvents()
    self:RegisterUiEvents()
    self:RegisterCommHandler()
    self:RegisterChatCommand("mpe", "OnSlashCommand")
    InitializeMplusEndorseUI()
end

--- Ensure AceDB is setup properly and the base expected structure is present if we're starting with a fresh db
--
-- @return void
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

--- Ensures we're responding to Blizzard events we care about using AceEvent.
--
-- Events we listen for:
-- * CHALLENGE_MODE_START - Used to determine when a M+ run has started
-- * CHALLENGE_MODE_COMPLETE - Used to determine when a M+ run has finished successfully (i.e. the run was completed, does NOT mean run beat timer)
-- * CHAT_MSG_SYSTEM - Used to determine when M+ run has failed because of instance reset
-- * GROUP_LEFT - Used to determine when a M+ run has failed because the group has started to disband
--
-- @return void
function MplusEndorse:RegisterBlizzardEvents()
    AceEvent:RegisterEvent("CHALLENGE_MODE_START", function()
        self:MythicPlusRunStarted()
    end)

    AceEvent:RegisterEvent("CHALLENGE_MODE_COMPLETED", function(event, info)
        self:MythicPlusRunFinished()
    end)

    -- TODO #14 do a better check to see if the group members leaving resulted in the party disbanding
    AceEvent:RegisterEvent("GROUP_LEFT", function(event, info)
        self:CheckActiveRunFailed()
    end)

    AceEvent:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
        local instanceResetSuccessRegex = string.gsub(INSTANCE_RESET_SUCCESS, "%%s", ".+")
        if string.match(msg, instanceResetSuccessRegex) then
            self:CheckActiveRunFailed()
            -- We need to let other members in the party that might be using this addon know that the leader reset the instance
            -- This chat message only shows up for the party leader, if we don't let other addon members know that the instance was reset (effectively ending the run)
            -- we'll still keep a value present in `activeRun` and the addon will believe that a M+ is in progress when really it failed.
            local instanceResetPayload = {type = MplusEndorse.CommEvents.InstanceReset}
            AceComm:SendCommMessage(MplusEndorse.CommPrefix, LunaJson.encode(instanceResetPayload), CommDistribution.Party)
        end
    end)

end

--- Ensures we're responding to events triggered by the UI that might cause db state to change.
-- For more information about each event please see the documentation on MplusEndorseEvents in src/Globals.lua
--
-- @return nil
function MplusEndorse:RegisterUiEvents()
    AceEvent:RegisterMessage(MplusEndorseEvents.Ui.OnPartyMemberEndorsed, function(_, info)
        self:EndorsePlayerForMythicPlus(info.run.id, info.member, info.score)
    end)
end

--- Ensure that we handle messages sent from other addon users
--
-- @return nil
function MplusEndorse:RegisterCommHandler()
    AceComm:RegisterComm("MplusEndorse", function(event, json, distribution, sender)
        -- Make sure we don't respond to our own events. This addon is intentionally designed so that anything that 
        -- a player might need to do for their own addon has already happened before we communicate to other addon 
        -- users. Allowing actions to happen for the player that sent the communication will only result in duplicative
        -- data being stored.
        if sender == UnitName("player") then
            return
        end

        local payload = LunaJson.decode(json)
        if payload.type == MplusEndorse.CommEvents.InstanceReset then
            self:CheckActiveRunFailed()
        elseif payload.type == MplusEndorse.CommEvents.PlayerEndorsed then
            self:Print(sender .. " gave " .. payload.player.name .. " a " .. payload.score)
        end
    end)
end

--- Ensures that M+ Endorse can respond to /mpe and show information that you've stored
--
-- @return nil
function MplusEndorse:OnSlashCommand(subcommand)
    if subcommand == "" then
        AceEvent:SendMessage(MplusEndorseEvents.App.ShowStatus, {runs = self.db.global.runs, players = self:GetAllSeenPlayerInfo()})
    else
        MplusEndorse:Print("Invalid command provided")
    end
end

--- Return a set of normalized information about the current party
-- Will iterate over all of the party members expected in a M+ and return a rich set of information about that party member.
--
-- @return {<PartyMember>, ...}
function MplusEndorse:GetPartyMembers()
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

--- Return a list of all player information for people that you have partied with in M+
-- Please note that the list will be across ALL characters for the account
--
-- @return {UnitGUID, ...}
function MplusEndorse:GetAllSeenPlayerInfo()
    local keys = {}
    for key,_ in pairs(self.db.global.players) do
        tinsert(keys, self:GetSeenPlayerInfo(key))
    end
    return keys
end

--- Return individual player information, including endorsement score, for the given UnitGUID.
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

--- Store that a player has been partied with for a specific M+ run.
--
-- @param runId string
-- @param player <PartyMember>
-- @return nil
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

--- Start tracking that a M+ run has started
-- When a M+ run is _finished_ there isn't enough information available to detail what level or dungeon or any other important info. This method
-- ensures that we have all that information to store when a run does actually end. This method should only be invoked when a M+ run has started,
-- otherwise assertion errors will be thrown on an active keystone not found.
-- 
-- @return nil
function MplusEndorse:MythicPlusRunStarted()
    local partyMembers = MplusEndorse:GetPartyMembers()
    local keystoneLevel, affixIds = C_ChallengeMode.GetActiveKeystoneInfo()
    local keystoneMapId = C_ChallengeMode.GetActiveChallengeMapID()
    local keystoneMapName = C_ChallengeMode.GetMapUIInfo(keystoneMapId)

    assert(keystoneLevel ~= nil, "Expected there to be an active keystone level but there is not one.")
    assert(keystoneMapId ~= nil, "Expected there to be an active keystone map ID but there is not one.")
    assert(keystoneMapName ~= nil, "Expected to retrieve a name for the keystone map ID but did not.")

    local playerGuid = UnitGUID("player")
    local now = GetServerTime()
    local affixes = {}
    for _, affixId in ipairs(affixIds) do
        local affixName = C_ChallengeMode.GetAffixInfo(affixId)
        tinsert(affixes, affixName)
    end
    
    -- There's no concept of generateing a GUID from the client in WoW so we need to come up with our own
    -- We can be safely sure that the same player will not be able to start more than 1 keystone within the same second, this feel like a safe assumption
    local runId = now .. "-" .. keystoneLevel .. "-" .. keystoneMapId .. "-" .. playerGuid
    local keystoneInfo = {
        id = runId,
        level = keystoneLevel,
        mapId = keystoneMapId,
        name = keystoneMapName,
        startedAt = now,
        affixes = affixes
    }

    for _, partyMember in pairs(partyMembers) do
        self:SeenPlayerInMythicPlus(runId, partyMember)
    end

    self.db.global.activeRun = {
        group = partyMembers,
        keystone = keystoneInfo
    }
end

--- Track that a M+ run has finished, storing data about the run, and triggering event to allow other parts of the addon to respond to the run finishing.
-- TODO #3 add ability to show the result of the run -1/1/2/3
-- @return nil
function MplusEndorse:MythicPlusRunFinished()
    assert(self.db.global.activeRun ~= nil, "Expected to have tracked an active keystone but did not find one.")

    local keystone = self.db.global.activeRun.keystone
    local group = self.db.global.activeRun.group
    self.db.global.activeRun = nil
    self.db.global.runs[keystone.id] = {
        playerId = UnitGUID("player"),
        player = UnitName("player"),
        realm = GetRealmName(),
        guild = GetGuildInfo("player"),
        level = keystone.level,
        challengeMapId = keystone.mapId,
        affxies = keystone.affixes,
        startedAt = keystone.startedAt,
        finishedAt = GetServerTime(),
        group = group
    }
    AceEvent:SendMessage(MplusEndorseEvents.App.MythicPlusRunFinished, {group = group, keystone = keystone})
end

--- Ensures that if the player enters a state where we think there is an active run but there's no active keystone being ran we detect that the M+ failed.
--
-- @return nil
function MplusEndorse:CheckActiveRunFailed()
    if self.db.global.activeRun ~= nil and C_ChallengeMode.IsChallengeModeActive() == false then
        self:MythicPlusRunFinished()
    end
end

--- Tracks that the user endorsed a party member for the given run
--
-- @param runId string
-- @param player <PartyMember>
-- @param score int
-- @return nil
function MplusEndorse:EndorsePlayerForMythicPlus(runId, player, score)
    self.db.global.players[player.id]["endorsements"][runId]["score"] = score
    local broadcastPayload = {
        type = self.Events.PlayerEndorsed,
        senderRunId = runId,
        player = player,
        score = score
    }

    -- This is a temporary message sent during development. Future changes will have a request to sync sent to friend/party/guild
    AceComm:SendCommMessage(MplusEndorse.CommPrefix, LunaJson.encode(broadcastPayload), CommDistribution.Party)
end
