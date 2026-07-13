-- Custom Chat Filter - Chat Hub
-- Options.lua

local CCF = CustomChatFilter
local panels, refreshers = {}, {}
local wordRows, channelRows, ignoreRows = {}, {}, {}
local wordOffset, channelOffset, ignoreOffset = 0, 0, 0

local function Panel(name, parent)
    local p = CreateFrame("Frame")
    p.name = name; p.parent = parent
    InterfaceOptions_AddCategory(p)
    return p
end

local function Title(panel, text, subtitle)
    local t=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); t:SetPoint("TOPLEFT",16,-16); t:SetText(text)
    if subtitle then local s=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); s:SetPoint("TOPLEFT",t,"BOTTOMLEFT",0,-6); s:SetWidth(590); s:SetJustifyH("LEFT"); s:SetText(subtitle) end
end

local function Heading(panel,text,x,y)
    local h=panel:CreateFontString(nil,"OVERLAY","GameFontNormal"); h:SetPoint("TOPLEFT",x,y); h:SetText(text); return h
end

local function Button(parent,text,width,height)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetWidth(width or 120); b:SetHeight(height or 24); b:SetText(text); return b
end

local function Input(parent,width,height)
    local e=CreateFrame("EditBox",nil,parent)
    e:SetWidth(width or 180); e:SetHeight(height or 24)
    e:SetAutoFocus(false); e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(6,6,0,0)
    e:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
    e:SetBackdropColor(0,0,0,.7); e:SetBackdropBorderColor(.55,.55,.55,1)
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    return e
end

local function Checkbox(panel,label,x,y,getter,setter)
    local c=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate"); c:SetWidth(24); c:SetHeight(24); c:SetPoint("TOPLEFT",x,y)
    local text=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight"); text:SetPoint("LEFT",c,"RIGHT",2,0); text:SetText(label)
    c:SetScript("OnClick",function(self) setter(self:GetChecked() and true or false); CCF:Fire("OPTIONS_UPDATED") end)
    table.insert(refreshers,function() c:SetChecked(getter() and true or false) end)
    return c
end

local function Slider(panel,name,label,x,y,width,min,max,step,getter,setter)
    local s=CreateFrame("Slider",name,panel,"OptionsSliderTemplate"); s:SetPoint("TOPLEFT",x,y); s:SetWidth(width); s:SetMinMaxValues(min,max); s:SetValueStep(step)
    _G[name.."Low"]:SetText(tostring(min)); _G[name.."High"]:SetText(tostring(max))
    s:SetScript("OnValueChanged",function(self,value)
        if self.updating then return end
        value=math.floor((value/step)+.5)*step; setter(value); _G[name.."Text"]:SetText(label..": "..value); CCF:Fire("OPTIONS_UPDATED")
    end)
    table.insert(refreshers,function()
        local v=getter(); s.updating=true; s:SetValue(v); s.updating=false
        _G[name.."Text"]:SetText(label..": "..v)
    end)
    return s
end

local function RefreshAll() local i for i=1,#refreshers do refreshers[i]() end end

local function Nav(panel,text,section,x,y)
    local b=Button(panel,text,180,28); b:SetPoint("TOPLEFT",x,y); b:SetScript("OnClick",function() CCF:OpenOptions(section) end); return b
end

local function CreateGeneral()
    local p=Panel("Custom Chat Filter"); panels.general=p
    Title(p,"Custom Chat Filter — Chat Hub","One chat scan powers custom filtering, spam training, LFG, and trade boards.")
    Heading(p,"Settings sections",18,-82)
    Nav(p,"LFG & Trade","boards",18,-104)
    Nav(p,"Spam Filter","filter",208,-104)
    Nav(p,"Spam Trainer","trainer",398,-104)
    Nav(p,"Ignored Players","ignored",18,-140)
    Nav(p,"Channel Sources","channels",208,-140)
    Heading(p,"Interface",18,-200)
    Checkbox(p,"Show minimap button",15,-218,function() return not CCF.db.minimap.hide end,function(v) CCF.db.minimap.hide=not v end)
    local open=Button(p,"Open Chat Hub",150,26); open:SetPoint("TOPLEFT",20,-260); open:SetScript("OnClick",function() CCF:OpenPage("lfg") end)
    local reset=Button(p,"Reset Window Size & Position",190,26); reset:SetPoint("LEFT",open,"RIGHT",10,0)
    reset:SetScript("OnClick",function()
        CCF.db.window.width=900; CCF.db.window.height=580; CCF.db.window.point="CENTER"; CCF.db.window.relativePoint="CENTER"; CCF.db.window.x=0; CCF.db.window.y=20
        CCF:Print("Window settings reset. Reopen or reload the Chat Hub.")
    end)
    Heading(p,"Current status",18,-326)
    p.status=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.status:SetPoint("TOPLEFT",20,-350); p.status:SetWidth(570); p.status:SetJustifyH("LEFT")
    table.insert(refreshers,function()
        p.status:SetText(string.format("Filter words: %d\nIgnored players: %d\nPending trainer suggestions: %d\nLFG board: %d entries\nTrade board: %d entries\nDiscovered channels: %d",#CCF.db.words,#CCF:GetIgnoredPlayers(),#CCF.db.trainer.pending,#CCF.boards.lfg,#CCF.boards.trade,CCF:CountTableEntries(CCF.db.discoveredChannels)))
    end)
    p.refresh=RefreshAll
end

local function RefreshWords()
    local p=panels.filter; if not p or not CCF.db then return end
    local total=#CCF.db.words; local maxOffset=math.max(0,total-#wordRows); if wordOffset>maxOffset then wordOffset=maxOffset end
    local i
    for i=1,#wordRows do
        local row=wordRows[i]; local n=i+wordOffset; local word=CCF.db.words[n]; row.actualIndex=n
        if word then row.text:SetText(n..". "..word); row:Show() else row:Hide() end
    end
    p.wordPage:SetText(total==0 and "No custom words yet" or ((wordOffset+1).."–"..math.min(wordOffset+#wordRows,total).." of "..total))
    if wordOffset>0 then p.wordPrev:Enable() else p.wordPrev:Disable() end
    if wordOffset<maxOffset then p.wordNext:Enable() else p.wordNext:Disable() end
end

local function CreateFilter()
    local p=Panel("Spam Filter","Custom Chat Filter"); panels.filter=p
    Title(p,"Spam Filter","Choose which chat sources use your custom words and non-Latin filter.")
    Checkbox(p,"Enable custom filtering",15,-72,function() return CCF.db.enabled end,function(v) CCF.db.enabled=v end)
    Checkbox(p,"Block clearly non-Latin writing systems",15,-100,function() return CCF.db.blockForeignScripts end,function(v) CCF.db.blockForeignScripts=v end)
    Heading(p,"Filter these chat types",18,-143)
    local sources={{"Say","say"},{"Yell","yell"},{"Emotes and text emotes","emote"},{"Incoming whispers","whisper"},{"Numbered and custom channels","channel"}}
    local i
    for i=1,#sources do
        local label,key=sources[i][1],sources[i][2]
        Checkbox(p,label,15,-160-((i-1)*27),function() return CCF.db.filterSources[key] end,function(v) CCF.db.filterSources[key]=v end)
    end
    local note=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); note:SetPoint("TOPLEFT",38,-302); note:SetWidth(260); note:SetJustifyH("LEFT"); note:SetText("Use Channel Sources to disable individual channels such as General, Global, or Trade.")

    Heading(p,"Custom words and phrases",325,-72)
    p.wordEdit=CreateFrame("EditBox",nil,p,"InputBoxTemplate"); p.wordEdit:SetWidth(190); p.wordEdit:SetHeight(24); p.wordEdit:SetPoint("TOPLEFT",329,-98); p.wordEdit:SetAutoFocus(false); p.wordEdit:SetMaxLetters(120)
    p.wordAdd=Button(p,"Add",55,22); p.wordAdd:SetPoint("LEFT",p.wordEdit,"RIGHT",5,0)
    p.wordAdd:SetScript("OnClick",function() local ok,msg=CCF:AddWord(p.wordEdit:GetText()); CCF:Print(msg); if ok then p.wordEdit:SetText(""); RefreshWords() end end)
    p.wordEdit:SetScript("OnEnterPressed",function(self) p.wordAdd:Click(); self:ClearFocus() end)
    for i=1,12 do
        local row=CreateFrame("Frame",nil,p); row:SetWidth(270); row:SetHeight(25); row:SetPoint("TOPLEFT",p.wordEdit,"BOTTOMLEFT",-4,-8-((i-1)*26))
        if i%2==0 then local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1,1,1,.04) end
        row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.text:SetPoint("LEFT",4,0); row.text:SetWidth(225); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
        row.remove=Button(row,"X",28,20); row.remove:SetPoint("RIGHT",-2,0)
        row.remove:SetScript("OnClick",function(self) local r=self:GetParent(); if r.actualIndex and CCF.db.words[r.actualIndex] then local ok,msg=CCF:RemoveWord(tostring(r.actualIndex)); CCF:Print(msg); RefreshWords() end end)
        wordRows[i]=row
    end
    p.wordPrev=Button(p,"<",55,21); p.wordPrev:SetPoint("TOPLEFT",p.wordEdit,"BOTTOMLEFT",-4,-325)
    p.wordNext=Button(p,">",55,21); p.wordNext:SetPoint("LEFT",p.wordPrev,"RIGHT",160,0)
    p.wordPage=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.wordPage:SetPoint("LEFT",p.wordPrev,"RIGHT",5,0); p.wordPage:SetWidth(150); p.wordPage:SetJustifyH("CENTER")
    p.wordPrev:SetScript("OnClick",function() wordOffset=math.max(0,wordOffset-#wordRows); RefreshWords() end)
    p.wordNext:SetScript("OnClick",function() wordOffset=wordOffset+#wordRows; RefreshWords() end)
    table.insert(refreshers,RefreshWords); p.refresh=RefreshAll
end

local function CreateTrainer()
    local p=Panel("Spam Trainer","Custom Chat Filter"); panels.trainer=p
    Title(p,"Spam Trainer","Learns from repeated messages, but never adds a filter without your approval.")
    Checkbox(p,"Enable repeat-message training",15,-72,function() return CCF.db.trainer.enabled end,function(v) CCF.db.trainer.enabled=v end)
    Checkbox(p,"Do not treat LFG adverts as spam",15,-100,function() return CCF.db.trainer.ignoreLFG end,function(v) CCF.db.trainer.ignoreLFG=v end)
    Checkbox(p,"Do not treat trade adverts as spam",15,-128,function() return CCF.db.trainer.ignoreTrade end,function(v) CCF.db.trainer.ignoreTrade=v end)
    Heading(p,"Train from these chat types",18,-171)
    local sources={{"Say","say"},{"Yell","yell"},{"Emotes and text emotes","emote"},{"Numbered and custom channels","channel"}}
    local i
    for i=1,#sources do
        local label,key=sources[i][1],sources[i][2]
        Checkbox(p,label,15,-188-((i-1)*27),function() return CCF.db.trainer.sources[key] end,function(v) CCF.db.trainer.sources[key]=v; CCF.recentSpam={} end)
    end
    Slider(p,"CustomChatFilterThresholdSliderV21","Repeats required",30,-334,250,2,10,1,function() return CCF.db.trainer.threshold end,function(v) CCF.db.trainer.threshold=v; CCF.recentSpam={} end)
    Slider(p,"CustomChatFilterWindowSliderV21","Repeat window (seconds)",30,-395,250,30,600,30,function() return CCF.db.trainer.windowSeconds end,function(v) CCF.db.trainer.windowSeconds=v; CCF.recentSpam={} end)
    local def=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); def:SetPoint("TOPLEFT",35,-450); def:SetWidth(260); def:SetJustifyH("LEFT"); def:SetText("Default: 4 matching posts within 90 seconds.")
    Heading(p,"Suggestions",335,-72)
    p.pending=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.pending:SetPoint("TOPLEFT",337,-99); p.pending:SetWidth(250); p.pending:SetJustifyH("LEFT")
    table.insert(refreshers,function() p.pending:SetText(#CCF.db.trainer.pending.." pending suggestion(s)\n"..CCF:CountTableEntries(CCF.db.trainer.ignored).." dismissed pattern(s)") end)
    local open=Button(p,"Open Suggestions",150,26); open:SetPoint("TOPLEFT",337,-155); open:SetScript("OnClick",function() CCF:OpenPage("trainer") end)
    local clear=Button(p,"Dismiss All Pending",150,26); clear:SetPoint("TOPLEFT",open,"BOTTOMLEFT",0,-10); clear:SetScript("OnClick",function() local a,d=CCF:FinalizeSuggestions({}); CCF:Print(d.." pending suggestion(s) dismissed."); RefreshAll() end)
    local reset=Button(p,"Reset Dismissed Patterns",175,26); reset:SetPoint("TOPLEFT",clear,"BOTTOMLEFT",0,-10); reset:SetScript("OnClick",function() CCF.db.trainer.ignored={}; CCF:Print("Dismissed-pattern history cleared."); RefreshAll() end)
    local note=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); note:SetPoint("TOPLEFT",reset,"BOTTOMLEFT",0,-14); note:SetWidth(255); note:SetJustifyH("LEFT"); note:SetText("The review window can add checked phrases and optionally add detected senders to CCF’s player ignore list.")
    p.refresh=RefreshAll
end

local function CreateBoards()
    local p=Panel("LFG & Trade","Custom Chat Filter"); panels.boards=p
    Title(p,"LFG & Trade","Separate collection and routing settings for the two live chat boards.")
    Heading(p,"Looking for Group",18,-72)
    Checkbox(p,"Collect LFG / LFM messages",15,-89,function() return CCF.db.boards.collectLFG end,function(v) CCF.db.boards.collectLFG=v end)
    Checkbox(p,"Hide captured LFG messages from normal chat",15,-117,function() return CCF.db.boards.hideLFG end,function(v) CCF.db.boards.hideLFG=v end)
    local li=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); li:SetPoint("TOPLEFT",38,-151); li:SetWidth(255); li:SetJustifyH("LEFT"); li:SetText("Detects Classic, TBC, and Wrath instances, common abbreviations, major bosses, raid size, difficulty, and requested roles.")
    Heading(p,"Trade",335,-72)
    Checkbox(p,"Collect WTS / WTB / WTT and profession requests",332,-89,function() return CCF.db.boards.collectTrade end,function(v) CCF.db.boards.collectTrade=v end)
    Checkbox(p,"Hide captured trade messages from normal chat",332,-117,function() return CCF.db.boards.hideTrade end,function(v) CCF.db.boards.hideTrade=v end)
    local ti=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); ti:SetPoint("TOPLEFT",355,-151); ti:SetWidth(245); ti:SetJustifyH("LEFT"); ti:SetText("The Trade page has quick filters for WTS, WTB, WTT, and profession/service requests.")

    Heading(p,"Board session",18,-215)
    Checkbox(p,"Clear LFG and Trade boards on login or /reload",15,-232,function() return CCF.db.boards.clearOnLogin end,function(v) CCF.db.boards.clearOnLogin=v end)

    Heading(p,"Scan these chat types for both boards",18,-275)
    local sources={{"Say","say"},{"Yell","yell"},{"Emotes and text emotes","emote"},{"Numbered and custom channels","channel"}}
    local i
    for i=1,#sources do
        local label,key=sources[i][1],sources[i][2]
        Checkbox(p,label,15,-292-((i-1)*27),function() return CCF.db.boards.sources[key] end,function(v) CCF.db.boards.sources[key]=v end)
    end
    Slider(p,"CustomChatFilterExpirySliderV21","Entry expiry (minutes)",335,-300,250,5,60,5,function() return CCF.db.boards.expiryMinutes end,function(v) CCF.db.boards.expiryMinutes=v end)
    Slider(p,"CustomChatFilterMaxEntriesSliderV21","Maximum entries per board",335,-370,250,50,400,50,function() return CCF.db.boards.maxEntries end,function(v) CCF.db.boards.maxEntries=v end)
    local ol=Button(p,"Open LFG Board",140,26); ol:SetPoint("TOPLEFT",20,-435); ol:SetScript("OnClick",function() CCF:OpenPage("lfg") end)
    local ot=Button(p,"Open Trade Board",140,26); ot:SetPoint("LEFT",ol,"RIGHT",10,0); ot:SetScript("OnClick",function() CCF:OpenPage("trade") end)
    local ow=Button(p,"Open Active Window",150,26); ow:SetPoint("LEFT",ot,"RIGHT",10,0); ow:SetScript("OnClick",function() CCF.db.activeWindow.hide=false; if CCF.ShowActiveWindow then CCF:ShowActiveWindow() end; CCF:Fire("OPTIONS_UPDATED") end)
    Checkbox(p,"Show standalone active-instances window",18,-475,function() return not CCF.db.activeWindow.hide end,function(v) CCF.db.activeWindow.hide=not v; if CCF.UpdateActiveWindowVisibility then CCF:UpdateActiveWindowVisibility() end end)
    local note=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); note:SetPoint("TOPLEFT",38,-505); note:SetWidth(570); note:SetJustifyH("LEFT"); note:SetText("The standalone window shows only currently active LFG instances so players can keep a compact overview while questing.")
    p.refresh=RefreshAll
end


local function RefreshIgnored()
    local p=panels.ignored
    if not p or not CCF.db then return end

    local players=CCF:GetIgnoredPlayers()
    local maxOffset=math.max(0,#players-#ignoreRows)
    if ignoreOffset>maxOffset then ignoreOffset=maxOffset end

    local i
    for i=1,#ignoreRows do
        local row=ignoreRows[i]
        local item=players[i+ignoreOffset]
        row.item=item

        if item then
            row.name:SetText((i+ignoreOffset)..". "..item.name)
            row.source:SetText(item.source and ("Added via "..item.source) or "")
            row:Show()
        else
            row:Hide()
        end
    end

    p.ignorePage:SetText(
        #players==0
            and "No ignored players"
            or ((ignoreOffset+1).."–"..math.min(ignoreOffset+#ignoreRows,#players).." of "..#players)
    )

    if ignoreOffset>0 then p.ignorePrev:Enable() else p.ignorePrev:Disable() end
    if ignoreOffset<maxOffset then p.ignoreNext:Enable() else p.ignoreNext:Disable() end
end

local function CreateIgnoredPlayers()
    local p=Panel("Ignored Players","Custom Chat Filter")
    panels.ignored=p

    Title(
        p,
        "Ignored Players",
        "CCF’s own account-wide ignore list. It does not modify WoW’s built-in ignore list."
    )

    Checkbox(
        p,
        "Enable CCF player ignore list",
        15,
        -72,
        function() return CCF.db.ignoreList.enabled end,
        function(v) CCF.db.ignoreList.enabled=v end
    )

    Checkbox(
        p,
        "Also hide ignored players in guild, party, raid, and battleground chat",
        15,
        -100,
        function() return CCF.db.ignoreList.includeGroupGuild end,
        function(v) CCF.db.ignoreList.includeGroupGuild=v end
    )

    Heading(p,"Add player",18,-145)

    p.ignoreEdit=Input(p,220,24)
    p.ignoreEdit:SetPoint("TOPLEFT",22,-170)
    p.ignoreEdit:SetMaxLetters(60)

    p.ignoreAdd=Button(p,"Ignore",75,22)
    p.ignoreAdd:SetPoint("LEFT",p.ignoreEdit,"RIGHT",6,0)

    p.ignoreAdd:SetScript("OnClick",function()
        local ok,msg=CCF:AddIgnoredPlayer(p.ignoreEdit:GetText(),"options")
        CCF:Print(msg)
        if ok then
            p.ignoreEdit:SetText("")
            RefreshIgnored()
        end
    end)

    p.ignoreEdit:SetScript("OnEnterPressed",function(self)
        p.ignoreAdd:Click()
        self:ClearFocus()
    end)

    local help=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    help:SetPoint("TOPLEFT",p.ignoreEdit,"BOTTOMLEFT",0,-8)
    help:SetWidth(500)
    help:SetJustifyH("LEFT")
    help:SetText(
        "You can also ignore players from LFG/Trade rows, from Spam Trainer suggestions, or with /ccf ignore PlayerName."
    )

    Heading(p,"Ignored player list",18,-245)

    local i
    for i=1,10 do
        local row=CreateFrame("Frame",nil,p)
        row:SetWidth(565)
        row:SetHeight(27)
        row:SetPoint("TOPLEFT",18,-268-((i-1)*28))

        if i%2==0 then
            local bg=row:CreateTexture(nil,"BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(1,1,1,.04)
        end

        row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        row.name:SetPoint("LEFT",4,0)
        row.name:SetWidth(255)
        row.name:SetJustifyH("LEFT")

        row.source=row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
        row.source:SetPoint("LEFT",265,0)
        row.source:SetWidth(220)
        row.source:SetJustifyH("LEFT")

        row.remove=Button(row,"Remove",65,20)
        row.remove:SetPoint("RIGHT",-2,0)
        row.remove:SetScript("OnClick",function(self)
            local item=self:GetParent().item
            if item then
                local ok,msg=CCF:RemoveIgnoredPlayer(item.key)
                CCF:Print(msg)
                RefreshIgnored()
            end
        end)

        ignoreRows[i]=row
    end

    p.ignorePrev=Button(p,"< Previous",85,22)
    p.ignorePrev:SetPoint("TOPLEFT",20,-558)

    p.ignoreNext=Button(p,"Next >",85,22)
    p.ignoreNext:SetPoint("TOPLEFT",500,-558)

    p.ignorePage=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.ignorePage:SetPoint("TOP",0,-563)
    p.ignorePage:SetWidth(260)
    p.ignorePage:SetJustifyH("CENTER")

    p.ignorePrev:SetScript("OnClick",function()
        ignoreOffset=math.max(0,ignoreOffset-#ignoreRows)
        RefreshIgnored()
    end)

    p.ignoreNext:SetScript("OnClick",function()
        ignoreOffset=ignoreOffset+#ignoreRows
        RefreshIgnored()
    end)

    table.insert(refreshers,RefreshIgnored)
    CCF:RegisterCallback("IGNORES_UPDATED",RefreshIgnored)
    p.refresh=RefreshAll
end

local function RefreshChannels()
    local p=panels.channels; if not p or not CCF.db then return end
    local channels=CCF:GetDiscoveredChannelList(); local maxOffset=math.max(0,#channels-#channelRows); if channelOffset>maxOffset then channelOffset=maxOffset end
    local i
    for i=1,#channelRows do
        local row=channelRows[i]; local item=channels[i+channelOffset]; row.item=item
        if item then row.name:SetText(item.name); row.filter:SetChecked(CCF:GetChannelSetting(item.key,"filter")); row.trainer:SetChecked(CCF:GetChannelSetting(item.key,"trainer")); row.boards:SetChecked(CCF:GetChannelSetting(item.key,"boards")); row:Show()
        else row:Hide() end
    end
    p.channelPage:SetText(#channels==0 and "No channels discovered yet" or ((channelOffset+1).."–"..math.min(channelOffset+#channelRows,#channels).." of "..#channels))
    if channelOffset>0 then p.channelPrev:Enable() else p.channelPrev:Disable() end
    if channelOffset<maxOffset then p.channelNext:Enable() else p.channelNext:Disable() end
end

local function SetAllChannels(field,value)
    local channels=CCF:GetDiscoveredChannelList(); local i
    for i=1,#channels do CCF:SetChannelSetting(channels[i].key,field,value) end
    RefreshChannels()
end

local function CreateChannels()
    local p=Panel("Channel Sources","Custom Chat Filter"); panels.channels=p
    Title(p,"Channel Sources","Channels appear after CCF sees a message in them. Control each scanner independently.")
    local n=p:CreateFontString(nil,"OVERLAY","GameFontNormal"); n:SetPoint("TOPLEFT",22,-82); n:SetText("Discovered channel")
    local f=p:CreateFontString(nil,"OVERLAY","GameFontNormal"); f:SetPoint("TOPLEFT",330,-82); f:SetText("Filter")
    local t=p:CreateFontString(nil,"OVERLAY","GameFontNormal"); t:SetPoint("TOPLEFT",405,-82); t:SetText("Trainer")
    local b=p:CreateFontString(nil,"OVERLAY","GameFontNormal"); b:SetPoint("TOPLEFT",495,-82); b:SetText("Boards")
    local i
    for i=1,12 do
        local row=CreateFrame("Frame",nil,p); row:SetWidth(565); row:SetHeight(30); row:SetPoint("TOPLEFT",18,-104-((i-1)*31))
        if i%2==0 then local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1,1,1,.04) end
        row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlight"); row.name:SetPoint("LEFT",4,0); row.name:SetWidth(285); row.name:SetJustifyH("LEFT")
        row.filter=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate"); row.filter:SetWidth(24); row.filter:SetHeight(24); row.filter:SetPoint("LEFT",305,0)
        row.trainer=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate"); row.trainer:SetWidth(24); row.trainer:SetHeight(24); row.trainer:SetPoint("LEFT",390,0)
        row.boards=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate"); row.boards:SetWidth(24); row.boards:SetHeight(24); row.boards:SetPoint("LEFT",480,0)
        row.filter:SetScript("OnClick",function(self) local item=self:GetParent().item; if item then CCF:SetChannelSetting(item.key,"filter",self:GetChecked()) end end)
        row.trainer:SetScript("OnClick",function(self) local item=self:GetParent().item; if item then CCF:SetChannelSetting(item.key,"trainer",self:GetChecked()) end end)
        row.boards:SetScript("OnClick",function(self) local item=self:GetParent().item; if item then CCF:SetChannelSetting(item.key,"boards",self:GetChecked()) end end)
        channelRows[i]=row
    end
    p.channelPrev=Button(p,"< Previous",85,22); p.channelPrev:SetPoint("TOPLEFT",20,-487)
    p.channelNext=Button(p,"Next >",85,22); p.channelNext:SetPoint("TOPLEFT",500,-487)
    p.channelPage=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.channelPage:SetPoint("TOP",0,-492); p.channelPage:SetWidth(260); p.channelPage:SetJustifyH("CENTER")
    p.channelPrev:SetScript("OnClick",function() channelOffset=math.max(0,channelOffset-#channelRows); RefreshChannels() end)
    p.channelNext:SetScript("OnClick",function() channelOffset=channelOffset+#channelRows; RefreshChannels() end)
    local fo=Button(p,"All Filter On",105,22); fo:SetPoint("TOPLEFT",20,-530); fo:SetScript("OnClick",function() SetAllChannels("filter",true) end)
    local ff=Button(p,"All Filter Off",105,22); ff:SetPoint("LEFT",fo,"RIGHT",5,0); ff:SetScript("OnClick",function() SetAllChannels("filter",false) end)
    local to=Button(p,"All Trainer On",110,22); to:SetPoint("LEFT",ff,"RIGHT",15,0); to:SetScript("OnClick",function() SetAllChannels("trainer",true) end)
    local tf=Button(p,"All Trainer Off",110,22); tf:SetPoint("LEFT",to,"RIGHT",5,0); tf:SetScript("OnClick",function() SetAllChannels("trainer",false) end)
    local bo=Button(p,"All Boards On",105,22); bo:SetPoint("TOPLEFT",20,-562); bo:SetScript("OnClick",function() SetAllChannels("boards",true) end)
    local bf=Button(p,"All Boards Off",105,22); bf:SetPoint("LEFT",bo,"RIGHT",5,0); bf:SetScript("OnClick",function() SetAllChannels("boards",false) end)
    table.insert(refreshers,RefreshChannels); CCF:RegisterCallback("CHANNELS_UPDATED",RefreshChannels); p.refresh=RefreshAll
end

function CCF:OpenOptions(section)
    local key=self:Lower(section or "")
    if key=="ignore" or key=="ignorelist" then key="ignored" end
    local target=panels[key] or ((key=="lfg" or key=="trade") and panels.boards) or panels.general
    if not target then return end
    InterfaceOptionsFrame_OpenToCategory(target); InterfaceOptionsFrame_OpenToCategory(target)
end

local function Init()
    CreateGeneral(); CreateBoards(); CreateFilter(); CreateTrainer(); CreateIgnoredPlayers(); CreateChannels()
    CCF:RegisterCallback("WORDS_UPDATED",RefreshWords); CCF:RegisterCallback("TRAINER_UPDATED",RefreshAll)
    CCF:RegisterCallback("OPTIONS_UPDATED",RefreshAll); CCF:RegisterCallback("BOARD_UPDATED",RefreshAll)
    CCF:RegisterCallback("IGNORES_UPDATED",RefreshAll)
    RefreshAll()
end

CCF:RegisterReady(Init)
