-- Custom Chat Filter - Chat Hub
-- UI.lua

local CCF = CustomChatFilter
local hub, menu, minimapButton, activeWindow
local ICON_PATH = "Interface\\AddOns\\CustomChatFilter\\Media\\CCFMinimapIcon"
local page = "lfg"
local boardOffset, trainerOffset, activityOffset = 0, 0, 0
local selectedActivities, trainerChecks, trainerIgnoreChecks = {}, {}, {}
local tradeFilter, searchText = "ALL", ""
local boardRows, trainerRows, activityRows, activeRows = {}, {}, {}, {}
local MAX_BOARD, MAX_TRAINER, MAX_ACTIVITY, MAX_ACTIVE_WINDOW = 22, 15, 18, 10
local shownBoard, shownTrainer, shownActivity = 10, 8, 10

local function Backdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
end

local function Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 100); b:SetHeight(height or 22); b:SetText(text)
    return b
end

local function Show(frame, value) if value then frame:Show() else frame:Hide() end end
local function Enable(button, value) if value then button:Enable() else button:Disable() end end

local function Age(timestamp)
    local seconds = math.max(0, time() - (timestamp or time()))
    if seconds < 60 then return seconds .. "s" end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return minutes .. "m" end
    return math.floor(minutes / 60) .. "h"
end

local function Clock(timestamp)
    if not timestamp then return "—" end
    return date("%H:%M", timestamp)
end

local function Tell(author)
    if not author or author == "" then return end
    if ChatFrame_SendTell then ChatFrame_SendTell(author)
    elseif ChatFrame1EditBox then
        ChatFrame1EditBox:Show(); ChatFrame1EditBox:SetFocus()
        ChatFrame1EditBox:SetText("/w " .. author .. " ")
    end
end

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

local function UpdateMinimapPosition()
    if not minimapButton or not CCF.db then return end
    local angle = math.rad(CCF.db.minimap.angle or 225)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local function UpdateBadge()
    if not minimapButton or not CCF.db then return end
    local count = #CCF.db.trainer.pending
    if count > 0 then
        minimapButton.badgeText:SetText(count > 99 and "99+" or tostring(count))
        minimapButton.badge:Show()
    else minimapButton.badge:Hide() end
end

function CCF:UpdateMinimapVisibility()
    if not minimapButton or not self.db then return end
    if self.db.minimap.hide then minimapButton:Hide()
    else minimapButton:Show(); UpdateMinimapPosition() end
end

local function ActiveInstanceCount()
    local active = CCF:GetActiveActivities()
    local count, index = 0, nil

    for index = 1, #active do
        if active[index].activity and active[index].activity.kind ~= "Boss" then
            count = count + 1
        end
    end

    return count
end

local function MenuLabels()
    if not menu or not CCF.db then return end
    menu.buttons[1]:SetText("LFG  (" .. #CCF.boards.lfg .. ")")
    menu.buttons[2]:SetText("Active Instances  (" .. ActiveInstanceCount() .. ")")
    menu.buttons[3]:SetText("Trade  (" .. #CCF.boards.trade .. ")")
    menu.buttons[4]:SetText("Spam Suggestions  (" .. #CCF.db.trainer.pending .. ")")
end

local function CreateMinimap()
    minimapButton = CreateFrame("Button", "CustomChatFilterMinimapButton", Minimap)
    minimapButton:SetWidth(34); minimapButton:SetHeight(34); minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetMovable(true); minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    minimapButton.icon:SetAllPoints()
    minimapButton.icon:SetTexture(ICON_PATH)
    minimapButton.icon:SetTexCoord(0.0, 1.0, 0.0, 1.0)

    minimapButton.highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    minimapButton.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    minimapButton.highlight:SetBlendMode("ADD")
    minimapButton.highlight:SetAlpha(0.45)
    minimapButton.highlight:SetPoint("CENTER", 0, 0)
    minimapButton.highlight:SetWidth(28)
    minimapButton.highlight:SetHeight(28)

    minimapButton.badge = CreateFrame("Frame", nil, minimapButton)
    minimapButton.badge:SetWidth(20); minimapButton.badge:SetHeight(16)
    minimapButton.badge:SetPoint("TOPRIGHT", 6, 5)
    minimapButton.badge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left=2,right=2,top=2,bottom=2 } })
    minimapButton.badge:SetBackdropColor(0.7, 0.1, 0.1, 1)
    minimapButton.badgeText = minimapButton.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapButton.badgeText:SetPoint("CENTER")

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Custom Chat Filter", 1, 1, 1)
        GameTooltip:AddLine("Left-click: quick menu", .8, .8, .8)
        GameTooltip:AddLine("Right-click: options", .8, .8, .8)
        GameTooltip:AddLine("Drag: move", .8, .8, .8)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then menu:Hide(); CCF:OpenOptions()
        elseif menu:IsShown() then menu:Hide()
        else MenuLabels(); menu:ClearAllPoints(); menu:SetPoint("TOPRIGHT", minimapButton, "BOTTOMLEFT", -2, -2); menu:Show() end
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local scale = Minimap:GetEffectiveScale()
            local x, y = GetCursorPosition(); x, y = x / scale, y / scale
            local cx, cy = Minimap:GetCenter()
            CCF.db.minimap.angle = math.deg(Atan2(y - cy, x - cx))
            UpdateMinimapPosition()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    UpdateBadge(); CCF:UpdateMinimapVisibility()
end

local function CreateMenu()
    menu = CreateFrame("Frame", "CustomChatFilterMinimapMenu", UIParent)
    menu:SetWidth(245); menu:SetHeight(156); menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true)
    Backdrop(menu); menu:Hide()
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12); title:SetText("CCF Chat Hub")
    menu.buttons = {}
    local names = {
        "LFG",
        "Active Instances",
        "Trade",
        "Spam Suggestions",
    }
    local index
    for index = 1, 4 do
        menu.buttons[index] = Button(menu, names[index], 215, 24)
        menu.buttons[index]:SetPoint("TOP", 0, -28 - ((index - 1) * 27))
    end
    menu.buttons[1]:SetScript("OnClick", function() menu:Hide(); CCF:OpenPage("lfg") end)
    menu.buttons[2]:SetScript("OnClick", function() menu:Hide(); CCF:ToggleActiveWindow(); CCF:Fire("OPTIONS_UPDATED") end)
    menu.buttons[3]:SetScript("OnClick", function() menu:Hide(); CCF:OpenPage("trade") end)
    menu.buttons[4]:SetScript("OnClick", function() menu:Hide(); CCF:OpenPage("trainer") end)
    table.insert(UISpecialFrames, "CustomChatFilterMinimapMenu")
end

local function ActivityLabel(activity, long)
    if not activity then return "" end
    if activity.kind == "Boss" then
        local parent = CCF.activityById[activity.parent]
        if parent then return parent.short .. (long and " — " or ": ") .. (long and activity.name or activity.short) end
    end
    return long and (activity.short .. " — " .. activity.name) or activity.short
end

local function Meta(entry)
    if not entry or not entry.meta then return "" end
    local p, roles = {}, {}
    if entry.meta.size then table.insert(p, tostring(entry.meta.size)) end
    if entry.meta.difficulty then table.insert(p, entry.meta.difficulty) end
    if entry.meta.roles.tank then table.insert(roles, "Tank") end
    if entry.meta.roles.healer then table.insert(roles, "Heal") end
    if entry.meta.roles.dps then table.insert(roles, "DPS") end
    if #roles > 0 then table.insert(p, table.concat(roles, "/")) end
    return table.concat(p, " · ")
end

local function PrimaryTag(entry, category)
    if category == "trade" then return entry.tradeType or "Trade" end
    local id = entry.activities and entry.activities[1]
    return id and ActivityLabel(CCF.activityById[id], false) or "LFG"
end

local function CreateBoardRow(parent, index)
    local row = CreateFrame("Frame", nil, parent); row:SetHeight(29)
    if index % 2 == 0 then local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1,1,1,.035) end
    row.author = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); row.author:SetPoint("LEFT",4,0); row.author:SetWidth(105); row.author:SetJustifyH("LEFT")
    row.tag = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); row.tag:SetPoint("LEFT",112,0); row.tag:SetWidth(84); row.tag:SetJustifyH("LEFT")
    row.message = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.message:SetPoint("LEFT",200,0); row.message:SetPoint("RIGHT",-183,0); row.message:SetJustifyH("LEFT"); row.message:SetWordWrap(false)
    row.age = row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); row.age:SetPoint("RIGHT",-134,0); row.age:SetWidth(42); row.age:SetJustifyH("RIGHT")
    row.ignore = Button(row,"Ignore",55,21); row.ignore:SetPoint("RIGHT",-70,0)
    row.tell = Button(row,"Whisper",64,21); row.tell:SetPoint("RIGHT",-3,0)
    row.hit = CreateFrame("Button",nil,row); row.hit:SetPoint("TOPLEFT"); row.hit:SetPoint("BOTTOMRIGHT",-131,0)
    row.hit:SetScript("OnClick", function(self) local e=self:GetParent().entry; if e then Tell(e.author) end end)
    row.tell:SetScript("OnClick", function(self) local e=self:GetParent().entry; if e then Tell(e.author) end end)
    row.ignore:SetScript("OnClick", function(self)
        local e=self:GetParent().entry
        if e then
            local success,message=CCF:AddIgnoredPlayer(e.author,"LFG/Trade board")
            CCF:Print(message)
            if success then CCF:RefreshHub() end
        end
    end)
    row.ignore:SetScript("OnEnter", function(self)
        local e=self:GetParent().entry
        if not e then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Ignore "..tostring(e.author),1,1,1)
        GameTooltip:AddLine("Hides future messages from this player and removes their current board entries.",.8,.8,.8,true)
        GameTooltip:Show()
    end)
    row.ignore:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.hit:SetScript("OnEnter", function(self)
        local e=self:GetParent().entry; if not e then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(e.author or "?",1,1,1); GameTooltip:AddLine(e.message or "",.9,.9,.9,true)
        local i
        for i=1,#(e.activities or {}) do local a=CCF.activityById[e.activities[i]]; if a then GameTooltip:AddLine("  "..ActivityLabel(a,true),.6,.8,1) end end
        local m=Meta(e); if m~="" then GameTooltip:AddLine(m,.6,1,.6) end
        if (e.count or 1)>1 then GameTooltip:AddLine("Repeated "..e.count.." times",.7,.7,.7) end
        GameTooltip:Show()
    end)
    row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function CreateTrainerRow(parent, index)
    local row=CreateFrame("Frame",nil,parent); row:SetHeight(50); row:EnableMouse(true)
    if index%2==0 then local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1,1,1,.035) end

    row.check=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate")
    row.check:SetWidth(24); row.check:SetHeight(24); row.check:SetPoint("LEFT",2,0)

    row.phrase=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.phrase:SetPoint("TOPLEFT",30,-5); row.phrase:SetPoint("RIGHT",-178,0); row.phrase:SetJustifyH("LEFT")

    row.example=row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    row.example:SetPoint("BOTTOMLEFT",30,5); row.example:SetPoint("RIGHT",-178,0)
    row.example:SetJustifyH("LEFT"); row.example:SetWordWrap(false)

    row.stats=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.stats:SetPoint("TOPRIGHT",-5,-6); row.stats:SetWidth(155); row.stats:SetJustifyH("RIGHT")

    row.ignoreCheck=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate")
    row.ignoreCheck:SetWidth(22); row.ignoreCheck:SetHeight(22)
    row.ignoreCheck:SetPoint("BOTTOMRIGHT",-128,2)

    row.ignoreText=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.ignoreText:SetPoint("LEFT",row.ignoreCheck,"RIGHT",0,0)
    row.ignoreText:SetPoint("RIGHT",-5,0)
    row.ignoreText:SetJustifyH("LEFT")
    row.ignoreText:SetText("Ignore sender(s)")

    row.check:SetScript("OnClick", function(self)
        local e=self:GetParent().entry
        if e then trainerChecks[e.id]=self:GetChecked() and true or nil end
    end)

    row.ignoreCheck:SetScript("OnClick", function(self)
        local e=self:GetParent().entry
        if e then trainerIgnoreChecks[e.id]=self:GetChecked() and true or nil end
    end)

    row:SetScript("OnEnter", function(self)
        if not self.entry then return end

        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:AddLine('Suggested: "'..self.entry.phrase..'"',1,1,1)
        GameTooltip:AddLine(self.entry.example or "",.9,.9,.9,true)

        local authors=self.entry.authors or {}
        if #authors > 0 then
            GameTooltip:AddLine("Detected sender"..(#authors==1 and ":" or "s:"),.6,.8,1)
            local i
            for i=1,#authors do
                GameTooltip:AddLine("  "..authors[i],.8,.8,.8)
            end
        else
            GameTooltip:AddLine("Sender data unavailable for this older suggestion.",.7,.7,.7,true)
        end

        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function CreateActivityRow(parent)
    local row=CreateFrame("Frame",nil,parent); row:SetHeight(24)
    row.check=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate")
    row.check:SetWidth(24); row.check:SetHeight(24); row.check:SetPoint("LEFT",0,0)
    row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.text:SetPoint("LEFT",row.check,"RIGHT",2,0); row.text:SetPoint("RIGHT",-2,0); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row.button=CreateFrame("Button",nil,row)
    row.button:SetPoint("TOPLEFT",24,0); row.button:SetPoint("BOTTOMRIGHT",0,0)

    local function ToggleRow(self)
        local parentRow = self.activityId and self or self:GetParent()
        if parentRow and parentRow.activityId then
            local checked = not not parentRow.check:GetChecked()
            if self == parentRow.button then
                checked = not checked
                parentRow.check:SetChecked(checked)
            end
            selectedActivities[parentRow.activityId] = checked and true or nil
            boardOffset=0
            CCF:RefreshHub()
        end
    end

    row.check:SetScript("OnClick", ToggleRow)
    row.button:SetScript("OnClick", ToggleRow)
    row.button:SetScript("OnEnter", function(self)
        local parentRow = self:GetParent()
        local a=parentRow.activityId and CCF.activityById[parentRow.activityId]; if not a then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(ActivityLabel(a,true),1,1,1); GameTooltip:AddLine(a.kind.." · "..(a.expansion or ""),.7,.8,1); GameTooltip:Show()
    end)
    row.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function HasActivitySelection() local id for id in pairs(selectedActivities) do return true end return false end

local function FilteredBoard(category)
    CCF:PruneBoard(category)
    local result, source, index = {}, CCF.boards[category], nil
    for index=1,#source do
        local e, ok = source[index], true
        if searchText~="" then
            local h=CCF:Lower((e.author or "").." "..(e.message or "").." "..(e.channel or ""))
            ok=string.find(h,searchText,1,true)~=nil
        end
        if ok and category=="trade" and tradeFilter~="ALL" then ok=e.tradeType==tradeFilter end
        if ok and category=="lfg" and HasActivitySelection() then
            ok=false; local id
            for id in pairs(selectedActivities) do if e.activitySet and e.activitySet[id] then ok=true; break end end
        end
        if ok then table.insert(result,e) end
    end
    return result
end

local function RefreshActivities()
    if not hub or page~="lfg" then return end
    local active=CCF:GetActiveActivities(); local activeSet={}; local i,id
    for i=1,#active do activeSet[active[i].id]=true end
    for id in pairs(selectedActivities) do if not activeSet[id] then selectedActivities[id]=nil end end
    local maxOffset=math.max(0,#active-shownActivity); if activityOffset>maxOffset then activityOffset=maxOffset end
    for i=1,MAX_ACTIVITY do
        local row,item=activityRows[i],nil; if i<=shownActivity then item=active[i+activityOffset] end
        if item then row.activityId=item.id; row.text:SetText(ActivityLabel(item.activity,true).."  ("..item.count..")"); row.check:SetChecked(selectedActivities[item.id] and true or false); row:Show()
        else row.activityId=nil; row:Hide() end
    end
    hub.activityCount:SetText(#active==0 and "No active detected instances" or (#active.." active"))
    Enable(hub.activityPrev,activityOffset>0); Enable(hub.activityNext,activityOffset<maxOffset)
    local n=CCF:CountTableEntries(selectedActivities); hub.activityAll:SetText(n>0 and ("Show All ("..n.." selected)") or "Show All")
end

local function RefreshBoard()
    if not hub or not hub:IsShown() or (page~="lfg" and page~="trade") then return end
    local list=FilteredBoard(page); local total=#list; local maxOffset=math.max(0,total-shownBoard)
    if boardOffset>maxOffset then boardOffset=maxOffset end
    hub.title:SetText(page=="lfg" and "Looking for Group" or "Trade — WTS / WTB / WTT")
    local sessionStarted, lastUpdated = CCF:GetBoardSessionInfo(page)
    hub.subtitle:SetText(
        total.." matching entr"..(total==1 and "y" or "ies")
        .." · Session started "..Clock(sessionStarted)
        .." · Last message "..Clock(lastUpdated)
        .." · Expiry "..CCF.db.boards.expiryMinutes.."m"
    )
    local i
    for i=1,MAX_BOARD do
        local row,e=boardRows[i],nil; if i<=shownBoard then e=list[i+boardOffset] end; row.entry=e
        if e then
            row.author:SetText(e.author or "?"); row.tag:SetText("|cff66ccff["..PrimaryTag(e,page).."]|r")
            local repeatText=(e.count or 1)>1 and (" |cff777777x"..e.count.."|r") or ""
            local meta=Meta(e); local metaText=meta~="" and (" |cff88cc88"..meta.."|r") or ""
            row.message:SetText((e.message or "")..metaText..repeatText); row.age:SetText(Age(e.lastSeen)); row:Show()
        else row:Hide() end
    end
    Enable(hub.prevButton,boardOffset>0); Enable(hub.nextButton,boardOffset<maxOffset)
    hub.pageText:SetText(total==0 and "No matching messages" or ((boardOffset+1).."–"..math.min(boardOffset+shownBoard,total).." of "..total))
    if page=="lfg" then hub.hideCaptured:SetChecked(CCF.db.boards.hideLFG); hub.hideCapturedText:SetText("Hide captured LFG from normal chat"); RefreshActivities()
    else hub.hideCaptured:SetChecked(CCF.db.boards.hideTrade); hub.hideCapturedText:SetText("Hide captured trade from normal chat") end
end

local function RefreshTrainer()
    if not hub or not hub:IsShown() or page~="trainer" then return end
    local pending=CCF.db.trainer.pending; local total=#pending; local maxOffset=math.max(0,total-shownTrainer)
    if trainerOffset>maxOffset then trainerOffset=maxOffset end
    hub.title:SetText("Spam Trainer Suggestions"); hub.subtitle:SetText("Check phrases to filter and/or senders to ignore, then apply checked actions and dismiss the rest.")
    local i
    for i=1,MAX_TRAINER do
        local row,e=trainerRows[i],nil; if i<=shownTrainer then e=pending[i+trainerOffset] end; row.entry=e
        if e then
            row.phrase:SetText('#'..e.id..'  "'..(e.phrase or "")..'"')
            row.example:SetText("Example: "..(e.example or ""))
            row.stats:SetText("x"..(e.count or 0).." · "..(e.authorCount or 0).." sender"..((e.authorCount or 0)==1 and "" or "s"))
            row.check:SetChecked(trainerChecks[e.id] and true or false)
            row.ignoreCheck:SetChecked(trainerIgnoreChecks[e.id] and true or false)

            if e.authors and #e.authors > 0 then
                row.ignoreCheck:Enable()
                row.ignoreText:SetTextColor(1,1,1)
            else
                row.ignoreCheck:Disable()
                row.ignoreCheck:SetChecked(false)
                trainerIgnoreChecks[e.id]=nil
                row.ignoreText:SetTextColor(.5,.5,.5)
            end

            row:Show()
        else row:Hide() end
    end
    Enable(hub.prevButton,trainerOffset>0); Enable(hub.nextButton,trainerOffset<maxOffset)
    hub.pageText:SetText(total==0 and "No pending suggestions" or ((trainerOffset+1).."–"..math.min(trainerOffset+shownTrainer,total).." of "..total))
end

local function TradeHighlights()
    local map={ALL=hub.tradeAll,WTS=hub.tradeWTS,WTB=hub.tradeWTB,WTT=hub.tradeWTT,SERVICE=hub.tradeService}
    local k,b for k,b in pairs(map) do if k==tradeFilter then b:LockHighlight() else b:UnlockHighlight() end end
end

local function ApplyPage()
    local boardPage=page=="lfg" or page=="trade"
    Show(hub.boardContainer,boardPage); Show(hub.trainerContainer,page=="trainer")
    Show(hub.activityPanel,page=="lfg"); Show(hub.tradeToolbar,page=="trade")
    Show(hub.hideCaptured,boardPage); Show(hub.hideCapturedText,boardPage); Show(hub.clearButton,boardPage); Show(hub.clearAllButton,boardPage)
    Show(hub.finishTrainer,page=="trainer"); Show(hub.selectAll,page=="trainer"); Show(hub.selectNone,page=="trainer")
    Show(hub.searchLabel,boardPage); Show(hub.searchBox,boardPage)
    hub.boardContainer:ClearAllPoints(); hub.boardContainer:SetPoint("TOP",hub,"TOP",0,-132); hub.boardContainer:SetPoint("BOTTOM",hub,"BOTTOM",0,65); hub.boardContainer:SetPoint("RIGHT",hub,"RIGHT",-24,0)
    if page=="lfg" then hub.boardContainer:SetPoint("LEFT",hub.activityPanel,"RIGHT",8,0) else hub.boardContainer:SetPoint("LEFT",hub,"LEFT",24,0) end
    hub.trainerContainer:ClearAllPoints(); hub.trainerContainer:SetPoint("TOPLEFT",hub,"TOPLEFT",24,-118); hub.trainerContainer:SetPoint("BOTTOMRIGHT",hub,"BOTTOMRIGHT",-24,65)
end

function CCF:RefreshHub()
    if not hub then return end
    ApplyPage(); TradeHighlights()
    if page=="trainer" then RefreshTrainer() else RefreshBoard() end
    UpdateBadge(); MenuLabels()
end

local function Layout()
    if not hub then return end
    local height=hub:GetHeight() or 580
    shownBoard=math.max(6,math.min(MAX_BOARD,math.floor((height-205)/30)))
    shownTrainer=math.max(5,math.min(MAX_TRAINER,math.floor((height-195)/51)))
    shownActivity=math.max(6,math.min(MAX_ACTIVITY,math.floor((height-245)/24)))
    local i
    for i=1,MAX_BOARD do boardRows[i]:ClearAllPoints(); boardRows[i]:SetPoint("TOPLEFT",hub.boardContainer,"TOPLEFT",0,-((i-1)*30)); boardRows[i]:SetPoint("RIGHT",hub.boardContainer,"RIGHT",0,0) end
    for i=1,MAX_TRAINER do trainerRows[i]:ClearAllPoints(); trainerRows[i]:SetPoint("TOPLEFT",hub.trainerContainer,"TOPLEFT",0,-((i-1)*51)); trainerRows[i]:SetPoint("RIGHT",hub.trainerContainer,"RIGHT",0,0) end
    for i=1,MAX_ACTIVITY do activityRows[i]:ClearAllPoints(); activityRows[i]:SetPoint("TOPLEFT",hub.activityList,"TOPLEFT",0,-((i-1)*24)); activityRows[i]:SetPoint("RIGHT",hub.activityList,"RIGHT",0,0) end
    CCF:RefreshHub()
end

local function SaveWindow()
    if not hub or not CCF.db then return end
    local point,relativeTo,relativePoint,x,y=hub:GetPoint(1)
    CCF.db.window.point=point or "CENTER"; CCF.db.window.relativePoint=relativePoint or "CENTER"; CCF.db.window.x=x or 0; CCF.db.window.y=y or 0
    CCF.db.window.width=hub:GetWidth(); CCF.db.window.height=hub:GetHeight()
end


local function ActiveWindowEntries()
    local source = CCF:GetActiveActivities()
    local result, i = {}, nil
    for i=1,#source do
        if source[i].activity and source[i].activity.kind ~= "Boss" then
            table.insert(result, source[i])
        end
    end
    return result
end

local function SaveActiveWindow()
    if not activeWindow or not CCF.db then return end
    local point, relativeTo, relativePoint, x, y = activeWindow:GetPoint(1)
    CCF.db.activeWindow.point = point or "CENTER"
    CCF.db.activeWindow.relativePoint = relativePoint or "CENTER"
    CCF.db.activeWindow.x = x or 0
    CCF.db.activeWindow.y = y or 0
    CCF.db.activeWindow.width = activeWindow:GetWidth()
    CCF.db.activeWindow.height = activeWindow:GetHeight()
end

local function RefreshActiveWindow()
    if not activeWindow then return end
    local entries = ActiveWindowEntries()
    local total = #entries
    local maxRows = math.min(MAX_ACTIVE_WINDOW, math.max(4, math.floor(((activeWindow:GetHeight() or 250) - 70) / 20)))
    activeWindow.titleText:SetText("Active LFG Instances")
    activeWindow.subtitle:SetText(total == 0 and "No active instances right now" or (total .. " active instance" .. (total == 1 and "" or "s")))
    local i
    for i=1,MAX_ACTIVE_WINDOW do
        local row = activeRows[i]
        local item = i <= maxRows and entries[i] or nil
        row.item = item
        if item then
            row.name:SetText(ActivityLabel(item.activity, false))
            row.count:SetText("(" .. item.count .. ")")
            row.newText:SetText(item.isNew and "|cff55ff55NEW|r" or "")
            row:Show()
        else
            row:Hide()
        end
    end
    Show(activeWindow.emptyText, total == 0)
end

function CCF:UpdateActiveWindowVisibility()
    if not activeWindow or not self.db then return end
    if self.db.activeWindow.hide then activeWindow:Hide()
    else activeWindow:Show(); RefreshActiveWindow() end
end

function CCF:ShowActiveWindow()
    if not self.db then return end
    self.db.activeWindow.hide = false
    self:UpdateActiveWindowVisibility()
end

function CCF:HideActiveWindow()
    if not self.db then return end
    self.db.activeWindow.hide = true
    self:UpdateActiveWindowVisibility()
end

function CCF:ToggleActiveWindow()
    if not self.db then return end
    self.db.activeWindow.hide = not self.db.activeWindow.hide
    self:UpdateActiveWindowVisibility()
end

local function CreateActiveWindow()
    activeWindow = CreateFrame("Frame", "CustomChatFilterActiveWindow", UIParent)
    activeWindow:SetWidth(CCF.db.activeWindow.width or 235)
    activeWindow:SetHeight(CCF.db.activeWindow.height or 250)
    activeWindow:SetPoint(CCF.db.activeWindow.point or "CENTER", UIParent, CCF.db.activeWindow.relativePoint or "CENTER", CCF.db.activeWindow.x or 380, CCF.db.activeWindow.y or 40)
    activeWindow:SetFrameStrata("HIGH")
    activeWindow:SetMovable(true); activeWindow:EnableMouse(true); activeWindow:RegisterForDrag("LeftButton"); activeWindow:SetClampedToScreen(true)
    if activeWindow.SetResizable then activeWindow:SetResizable(true) end
    if activeWindow.SetMinResize then activeWindow:SetMinResize(190,150) end
    if activeWindow.SetMaxResize then activeWindow:SetMaxResize(340,420) end
    Backdrop(activeWindow)
    activeWindow:SetScript("OnDragStart", function(self) self:StartMoving() end)
    activeWindow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveActiveWindow() end)
    activeWindow:SetScript("OnSizeChanged", function() SaveActiveWindow(); RefreshActiveWindow() end)

    activeWindow.titleText = activeWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeWindow.titleText:SetPoint("TOP", 0, -12)
    activeWindow.subtitle = activeWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeWindow.subtitle:SetPoint("TOP", activeWindow.titleText, "BOTTOM", 0, -4)

    local close = CreateFrame("Button", nil, activeWindow, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() CCF:HideActiveWindow(); CCF:Fire("OPTIONS_UPDATED") end)

    local open = Button(activeWindow, "Open LFG Board", 120, 22)
    open:SetPoint("BOTTOMLEFT", 10, 10)
    open:SetScript("OnClick", function() CCF:OpenPage("lfg") end)

    local hide = Button(activeWindow, "Hide", 55, 22)
    hide:SetPoint("LEFT", open, "RIGHT", 5, 0)
    hide:SetScript("OnClick", function() CCF:HideActiveWindow(); CCF:Fire("OPTIONS_UPDATED") end)

    activeWindow.emptyText = activeWindow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    activeWindow.emptyText:SetPoint("CENTER", 0, 0)
    activeWindow.emptyText:SetText("No active instances")

    activeWindow.rowsContainer = CreateFrame("Frame", nil, activeWindow)
    activeWindow.rowsContainer:SetPoint("TOPLEFT", 10, -42)
    activeWindow.rowsContainer:SetPoint("BOTTOMRIGHT", -10, 40)

    local i
    for i=1,MAX_ACTIVE_WINDOW do
        local row = CreateFrame("Button", nil, activeWindow.rowsContainer)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", 0, -((i-1) * 20))
        row:SetPoint("RIGHT", 0, 0)
        if i % 2 == 0 then local bg=row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1,1,1,.04) end
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.count:SetPoint("RIGHT", -4, 0); row.count:SetWidth(30); row.count:SetJustifyH("RIGHT")
        row.newText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.newText:SetPoint("RIGHT", row.count, "LEFT", -4, 0); row.newText:SetWidth(32); row.newText:SetJustifyH("RIGHT")
        row.name:SetPoint("RIGHT", row.newText, "LEFT", -4, 0)
        row:SetScript("OnClick", function(self)
            if not self.item then return end
            selectedActivities = {}
            selectedActivities[self.item.id] = true
            page = "lfg"
            boardOffset = 0
            activityOffset = 0
            if hub then hub:Show() end
            CCF:RefreshHub()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ActivityLabel(self.item.activity, true), 1, 1, 1)
            GameTooltip:AddLine(self.item.count .. " active board post" .. (self.item.count == 1 and "" or "s"), .8, .8, .8)
            GameTooltip:AddLine("Click to open the main LFG board filtered to this activity.", .7, .9, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        activeRows[i] = row
    end

    local resize = CreateFrame("Button", nil, activeWindow)
    resize:SetWidth(16); resize:SetHeight(16); resize:SetPoint("BOTTOMRIGHT", -6, 6)
    local tex = resize:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(); tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetScript("OnMouseDown", function() if activeWindow.StartSizing then activeWindow:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp", function() activeWindow:StopMovingOrSizing(); SaveActiveWindow(); RefreshActiveWindow() end)
    resize:SetScript("OnEnter", function() tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
    resize:SetScript("OnLeave", function() tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)

    -- Deliberately not added to UISpecialFrames. That keeps this tracker pinned
    -- when fullscreen panels such as the world map are opened and closed.
    if activeWindow.SetToplevel then activeWindow:SetToplevel(true) end

    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnHide", function()
            if CCF.db and not CCF.db.activeWindow.hide then
                CCF:UpdateActiveWindowVisibility()
            end
        end)
    end

    CCF:UpdateActiveWindowVisibility()
end

local function CreateHub()
    hub=CreateFrame("Frame","CustomChatFilterHub",UIParent)
    hub:SetWidth(CCF.db.window.width or 900); hub:SetHeight(CCF.db.window.height or 580)
    hub:SetPoint(CCF.db.window.point or "CENTER",UIParent,CCF.db.window.relativePoint or "CENTER",CCF.db.window.x or 0,CCF.db.window.y or 20)
    hub:SetFrameStrata("DIALOG"); hub:SetMovable(true); hub:EnableMouse(true); hub:RegisterForDrag("LeftButton"); hub:SetClampedToScreen(true); Backdrop(hub); hub:Hide()
    if hub.SetResizable then hub:SetResizable(true) end; if hub.SetMinResize then hub:SetMinResize(760,460) end; if hub.SetMaxResize then hub:SetMaxResize(1200,850) end
    hub:SetScript("OnDragStart",function(self) self:StartMoving() end)
    hub:SetScript("OnDragStop",function(self) self:StopMovingOrSizing(); SaveWindow() end)
    hub:SetScript("OnSizeChanged",function(self) if CCF.db then CCF.db.window.width=self:GetWidth(); CCF.db.window.height=self:GetHeight() end; Layout() end)

    hub.title=hub:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); hub.title:SetPoint("TOP",0,-16)
    hub.subtitle=hub:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); hub.subtitle:SetPoint("TOP",hub.title,"BOTTOM",0,-5); hub.subtitle:SetPoint("LEFT",30,0); hub.subtitle:SetPoint("RIGHT",-30,0); hub.subtitle:SetJustifyH("CENTER")
    local close=CreateFrame("Button",nil,hub,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-5,-5)
    local lfg=Button(hub,"LFG",100,24); lfg:SetPoint("TOPLEFT",24,-55)
    local trade=Button(hub,"Trade",100,24); trade:SetPoint("LEFT",lfg,"RIGHT",5,0)
    local trainer=Button(hub,"Trainer",100,24); trainer:SetPoint("LEFT",trade,"RIGHT",5,0)
    local options=Button(hub,"Options",100,24); options:SetPoint("TOPRIGHT",-24,-55)
    lfg:SetScript("OnClick",function() page="lfg"; boardOffset=0; CCF:RefreshHub() end)
    trade:SetScript("OnClick",function() page="trade"; boardOffset=0; CCF:RefreshHub() end)
    trainer:SetScript("OnClick",function() page="trainer"; trainerOffset=0; CCF:RefreshHub() end)
    options:SetScript("OnClick",function() CCF:OpenOptions() end)

    hub.searchLabel=hub:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); hub.searchLabel:SetPoint("TOPLEFT",26,-91); hub.searchLabel:SetText("Search:")
    hub.searchBox=CreateFrame("EditBox",nil,hub,"InputBoxTemplate"); hub.searchBox:SetHeight(22); hub.searchBox:SetPoint("LEFT",hub.searchLabel,"RIGHT",7,0); hub.searchBox:SetPoint("RIGHT",-290,0); hub.searchBox:SetAutoFocus(false); hub.searchBox:SetMaxLetters(80)
    hub.searchBox:SetScript("OnTextChanged",function(self) searchText=CCF:Lower(CCF:Trim(self:GetText())); boardOffset=0; RefreshBoard() end)

    hub.activityPanel=CreateFrame("Frame",nil,hub); hub.activityPanel:SetWidth(205); hub.activityPanel:SetPoint("TOPLEFT",24,-120); hub.activityPanel:SetPoint("BOTTOMLEFT",24,66)
    hub.activityPanel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=3,right=3,top=3,bottom=3}}); hub.activityPanel:SetBackdropColor(0,0,0,.2)
    local at=hub.activityPanel:CreateFontString(nil,"OVERLAY","GameFontNormal"); at:SetPoint("TOPLEFT",9,-9); at:SetText("Active instances & bosses")
    hub.activityCount=hub.activityPanel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); hub.activityCount:SetPoint("TOPLEFT",at,"BOTTOMLEFT",0,-3)
    hub.activityAll=Button(hub.activityPanel,"Show All",180,22); hub.activityAll:SetPoint("TOP",0,-48); hub.activityAll:SetScript("OnClick",function() selectedActivities={}; activityOffset=0; boardOffset=0; CCF:RefreshHub() end)
    hub.activityList=CreateFrame("Frame",nil,hub.activityPanel); hub.activityList:SetPoint("TOPLEFT",8,-78); hub.activityList:SetPoint("BOTTOMRIGHT",-8,35)
    local i for i=1,MAX_ACTIVITY do activityRows[i]=CreateActivityRow(hub.activityList) end
    hub.activityPrev=Button(hub.activityPanel,"<",45,20); hub.activityPrev:SetPoint("BOTTOMLEFT",8,9)
    hub.activityNext=Button(hub.activityPanel,">",45,20); hub.activityNext:SetPoint("BOTTOMRIGHT",-8,9)
    hub.activityPrev:SetScript("OnClick",function() activityOffset=math.max(0,activityOffset-shownActivity); RefreshActivities() end)
    hub.activityNext:SetScript("OnClick",function() activityOffset=activityOffset+shownActivity; RefreshActivities() end)

    hub.tradeToolbar=CreateFrame("Frame",nil,hub); hub.tradeToolbar:SetHeight(26); hub.tradeToolbar:SetPoint("TOPLEFT",24,-115); hub.tradeToolbar:SetPoint("RIGHT",-24,0)
    local tl=hub.tradeToolbar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); tl:SetPoint("LEFT"); tl:SetText("Show:")
    hub.tradeAll=Button(hub.tradeToolbar,"All",60,22); hub.tradeAll:SetPoint("LEFT",tl,"RIGHT",8,0)
    hub.tradeWTS=Button(hub.tradeToolbar,"WTS",60,22); hub.tradeWTS:SetPoint("LEFT",hub.tradeAll,"RIGHT",4,0)
    hub.tradeWTB=Button(hub.tradeToolbar,"WTB",60,22); hub.tradeWTB:SetPoint("LEFT",hub.tradeWTS,"RIGHT",4,0)
    hub.tradeWTT=Button(hub.tradeToolbar,"WTT",60,22); hub.tradeWTT:SetPoint("LEFT",hub.tradeWTB,"RIGHT",4,0)
    hub.tradeService=Button(hub.tradeToolbar,"Services",75,22); hub.tradeService:SetPoint("LEFT",hub.tradeWTT,"RIGHT",4,0)
    local function SetTrade(v) tradeFilter=v; boardOffset=0; TradeHighlights(); RefreshBoard() end
    hub.tradeAll:SetScript("OnClick",function() SetTrade("ALL") end); hub.tradeWTS:SetScript("OnClick",function() SetTrade("WTS") end); hub.tradeWTB:SetScript("OnClick",function() SetTrade("WTB") end); hub.tradeWTT:SetScript("OnClick",function() SetTrade("WTT") end); hub.tradeService:SetScript("OnClick",function() SetTrade("SERVICE") end)

    hub.boardContainer=CreateFrame("Frame",nil,hub); for i=1,MAX_BOARD do boardRows[i]=CreateBoardRow(hub.boardContainer,i) end
    hub.trainerContainer=CreateFrame("Frame",nil,hub); for i=1,MAX_TRAINER do trainerRows[i]=CreateTrainerRow(hub.trainerContainer,i) end
    hub.prevButton=Button(hub,"< Previous",90,22); hub.prevButton:SetPoint("BOTTOMLEFT",25,27)
    hub.nextButton=Button(hub,"Next >",90,22); hub.nextButton:SetPoint("LEFT",hub.prevButton,"RIGHT",5,0)
    hub.pageText=hub:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); hub.pageText:SetPoint("LEFT",hub.nextButton,"RIGHT",12,0); hub.pageText:SetWidth(180); hub.pageText:SetJustifyH("LEFT")
    hub.clearButton=Button(hub,"Clear Board",100,22); hub.clearButton:SetPoint("BOTTOMRIGHT",-25,27)
    hub.clearAllButton=Button(hub,"Clear LFG + Trade",125,22); hub.clearAllButton:SetPoint("RIGHT",hub.clearButton,"LEFT",-5,0)
    hub.hideCaptured=CreateFrame("CheckButton",nil,hub,"UICheckButtonTemplate"); hub.hideCaptured:SetWidth(24); hub.hideCaptured:SetHeight(24); hub.hideCaptured:SetPoint("BOTTOMRIGHT",hub.clearButton,"TOPRIGHT",0,5)
    hub.hideCapturedText=hub:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); hub.hideCapturedText:SetPoint("RIGHT",hub.hideCaptured,"LEFT",-2,0); hub.hideCapturedText:SetJustifyH("RIGHT")
    hub.finishTrainer=Button(hub,"Apply Checked & Dismiss Rest",220,24); hub.finishTrainer:SetPoint("BOTTOMRIGHT",-25,26)
    hub.selectAll=Button(hub,"Check All Words",105,22); hub.selectAll:SetPoint("RIGHT",hub.finishTrainer,"LEFT",-8,0)
    hub.selectNone=Button(hub,"Clear All Checks",105,22); hub.selectNone:SetPoint("RIGHT",hub.selectAll,"LEFT",-5,0)

    hub.prevButton:SetScript("OnClick",function() if page=="trainer" then trainerOffset=math.max(0,trainerOffset-shownTrainer) else boardOffset=math.max(0,boardOffset-shownBoard) end; CCF:RefreshHub() end)
    hub.nextButton:SetScript("OnClick",function() if page=="trainer" then trainerOffset=trainerOffset+shownTrainer else boardOffset=boardOffset+shownBoard end; CCF:RefreshHub() end)
    hub.clearButton:SetScript("OnClick",function() CCF:ClearBoard(page); boardOffset=0; selectedActivities={}; CCF:RefreshHub() end)
    hub.clearAllButton:SetScript("OnClick",function() CCF:ClearAllBoards(true,"manual"); CCF:Print("LFG and Trade boards cleared; a new board session has started.") end)
    hub.hideCaptured:SetScript("OnClick",function(self) if page=="lfg" then CCF.db.boards.hideLFG=self:GetChecked() and true or false else CCF.db.boards.hideTrade=self:GetChecked() and true or false end; CCF:Fire("OPTIONS_UPDATED") end)
    hub.selectAll:SetScript("OnClick",function()
        local n
        for n=1,#CCF.db.trainer.pending do
            trainerChecks[CCF.db.trainer.pending[n].id]=true
        end
        RefreshTrainer()
    end)
    hub.selectNone:SetScript("OnClick",function()
        trainerChecks={}
        trainerIgnoreChecks={}
        RefreshTrainer()
    end)
    hub.finishTrainer:SetScript("OnClick",function()
        local added,dismissed,ignoredPlayers=
            CCF:FinalizeSuggestions(trainerChecks,trainerIgnoreChecks)
        trainerChecks={}
        trainerIgnoreChecks={}
        trainerOffset=0
        CCF:Print(
            added.." phrase(s) added; "
            ..ignoredPlayers.." player(s) ignored; "
            ..dismissed.." unchecked pattern(s) dismissed."
        )
        RefreshTrainer()
    end)
    hub.finishTrainer:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Apply Checked & Dismiss Rest",1,1,1)
        GameTooltip:AddLine(
            "Adds checked phrases, ignores sender(s) checked on each row, and dismisses every unchecked spam pattern.",
            .8,.8,.8,true
        )
        GameTooltip:Show()
    end)
    hub.finishTrainer:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local resize=CreateFrame("Button",nil,hub); resize:SetWidth(18); resize:SetHeight(18); resize:SetPoint("BOTTOMRIGHT",-7,7)
    local tex=resize:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetScript("OnMouseDown",function() if hub.StartSizing then hub:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp",function() hub:StopMovingOrSizing(); SaveWindow() end)
    resize:SetScript("OnEnter",function() tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
    resize:SetScript("OnLeave",function() tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)
    hub:SetScript("OnShow",function() Layout() end)
    table.insert(UISpecialFrames,"CustomChatFilterHub")
    Layout()
end

function CCF:OpenPage(which)
    page=(which=="lfg" or which=="trade" or which=="trainer") and which or "lfg"
    boardOffset,trainerOffset=0,0; if menu then menu:Hide() end; hub:Show(); self:RefreshHub()
end

local function ResetBoardViewState()
    selectedActivities = {}
    boardOffset = 0
    activityOffset = 0
    tradeFilter = "ALL"
    searchText = ""

    if hub and hub.searchBox then
        hub.searchBox:SetText("")
    end

    if hub then
        CCF:RefreshHub()
    end

    RefreshActiveWindow()
end

local function Init()
    CreateHub(); CreateMenu(); CreateMinimap(); CreateActiveWindow()
    CCF:RegisterCallback("BOARD_SESSION_RESET",ResetBoardViewState)
    CCF:RegisterCallback("BOARD_UPDATED",function(category) if hub and hub:IsShown() and page==category then CCF:RefreshHub() end; MenuLabels(); RefreshActiveWindow() end)
    CCF:RegisterCallback("TRAINER_UPDATED",function() UpdateBadge(); MenuLabels(); if hub and hub:IsShown() and page=="trainer" then RefreshTrainer() end end)
    CCF:RegisterCallback("IGNORES_UPDATED",function() MenuLabels(); if hub and hub:IsShown() then CCF:RefreshHub() end; RefreshActiveWindow() end)
    CCF:RegisterCallback("OPTIONS_UPDATED",function() CCF:UpdateMinimapVisibility(); CCF:UpdateActiveWindowVisibility(); CCF:RefreshHub() end)
    local ticker=CreateFrame("Frame"); ticker.elapsed=0
    ticker:SetScript("OnUpdate",function(self,elapsed) self.elapsed=self.elapsed+elapsed; if self.elapsed<5 then return end; self.elapsed=0; if hub and hub:IsShown() and page~="trainer" then CCF:RefreshHub() end; if activeWindow and activeWindow:IsShown() then RefreshActiveWindow() end end)
end

CCF:RegisterReady(Init)
