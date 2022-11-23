local AceGUI = LibStub("AceGUI-3.0")
local AceEvent = LibStub("AceEvent-3.0")
local MplusEndorseUI = {}

function InitializeMplusEndorseUI()
    AceEvent:RegisterMessage(MplusEndorseEvents.App.ShowStatus, function(_, payload)
        MplusEndorseUI:ShowStatus(payload.runs, payload.players)
    end)
end

function MplusEndorseUI:CreateAceFrame(title, layout, frameType)
    if frameType == nil then
        frameType = "Frame"
    end
    local frame = AceGUI:Create(frameType)
    frame:SetTitle(title)
    frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
    frame:SetLayout(layout)
    return frame
end

function MplusEndorseUI:ShowPartyEndorsement(partyMembers, keystoneInfo)
    local function partyMemberEndorsed(partyMemberGroup, endorsementType, labelHeight)
        partyMemberGroup:ReleaseChildren()
        local alreadyEndorsedLabel = AceGUI:Create("Label")
        alreadyEndorsedLabel:SetText("You gave a " .. endorsementType .. " for this run.")
        alreadyEndorsedLabel:SetFullWidth(true)
        alreadyEndorsedLabel:SetHeight(labelHeight)
        partyMemberGroup:AddChild(alreadyEndorsedLabel)
    end

    local endorseFrame = MplusEndorseUI:CreateAceFrame("M+ Endorsement", "List")
    local mPlusHeading = AceGUI:Create("Heading")
    
    mPlusHeading:SetText(keystoneInfo.level .. " " .. keystoneInfo.name)
    mPlusHeading:SetFullWidth(true)

    endorseFrame:AddChild(mPlusHeading)

    for index, partyInfo in pairs(partyMembers) do
        local partyId = partyInfo["id"]
        local name = partyInfo["name"] .. "-" .. partyInfo["realm"]
        local partyMemberGroup = AceGUI:Create("InlineGroup")
        local endorseUpButton = AceGUI:Create("Button")
        local endorseDownButton = AceGUI:Create("Button")

        partyMemberGroup:SetTitle(name)
        partyMemberGroup:SetLayout("Flow")
        partyMemberGroup:SetFullWidth(true)

        endorseUpButton:SetText("+1")
        endorseUpButton:SetCallback("OnClick", function()
            AceEvent:SendMessage(self.OnPartyMemberEndorsed, {member = partyInfo, run = keystoneInfo, score = 1})
            partyMemberEndorsed(partyMemberGroup, "+1", endorseUpButton:GetHeight())
        end)
        endorseDownButton:SetText("-1")
        endorseDownButton:SetCallback("OnClick", function()
            AceEvent:SendMessage(self.OnPartyMemberEndorsed, {member = partyInfo, run = keystoneInfo, score = -1})
            partyMemberEndorsed(partyMemberGroup, "-1", endorseDownButton:GetHeight())
        end)

        partyMemberGroup:AddChild(endorseUpButton)
        partyMemberGroup:AddChild(endorseDownButton)

        endorseFrame:AddChild(partyMemberGroup)
    end
end

function MplusEndorseUI:ShowStatus(runs, players)
    local function renderRuns(container)
        local scrollFrame = AceGUI:Create("ScrollFrame")
        scrollFrame:SetLayout("List")
        for runId, runInfo in pairs(runs) do
            local runLabel = AceGUI:Create("Label")
            runLabel:SetText(runId)
            scrollFrame:AddChild(runLabel)
        end
        container:AddChild(scrollFrame)
    end

    local function renderEndorsements(container)
        local scrollFrame = AceGUI:Create("ScrollFrame")
        scrollFrame:SetLayout("List")
        for _, player in pairs(players) do
            local playerGroup = AceGUI:Create("InlineGroup")
            playerGroup:SetTitle(player.name .. "-" .. player.realm)
            playerGroup:SetFullWidth(true)

            local scoreLabel = AceGUI:Create("Label")
            local numLabel = AceGUI:Create("Label")
            scoreLabel:SetText("Score: " .. player.score)
            numLabel:SetText("Number Endorsements: " .. player.numberOfEndorsements)

            playerGroup:AddChild(scoreLabel)
            playerGroup:AddChild(numLabel)
            
            scrollFrame:AddChild(playerGroup)
        end
        container:AddChild(scrollFrame)
    end

    local function selectTab(container, event, tab)
        container:ReleaseChildren()
        if tab == "runs" then
            renderRuns(container)
        elseif tab == "endorsements" then
            renderEndorsements(container)
        end
    end

    
    local tabsControl = AceGUI:Create("TabGroup")
    tabsControl:SetLayout("Fill")
    tabsControl:SetTabs({{text="Endorsements", value="endorsements"}})
    tabsControl:SetCallback("OnGroupSelected", selectTab)
    tabsControl:SelectTab("endorsements")

    local statusFrame = MplusEndorseUI:CreateAceFrame("M+ Endorsements", "Fill")
    statusFrame:EnableResize(false)
    statusFrame:AddChild(tabsControl)
end