-- Custom Chat Filter - Chat Hub
-- Core.lua
-- World of Warcraft 3.3.5a / Interface 30300

CustomChatFilter = CustomChatFilter or {}
local CCF = CustomChatFilter

CCF.VERSION = "2.3.0-beta.5"
CCF.PREFIX = "|cff33ff99CCF:|r "
CCF.ready = false
CCF.readyCallbacks = CCF.readyCallbacks or {}
CCF.callbacks = CCF.callbacks or {}
CCF.boards = CCF.boards or { lfg = {}, trade = {} }
CCF.boardSession = CCF.boardSession or {
    startedAt = time(),
    lastUpdated = { lfg = nil, trade = nil },
}
CCF.recentSpam = CCF.recentSpam or {}
CCF.dispatchCache = CCF.dispatchCache or {}
CCF.playerName = nil
CCF.activityById = {}
CCF.activityOrder = {}

-- Identical messages sent to several channels in quick succession are usually
-- one advert being cross-posted, not several repetitions.
local CROSS_POST_GRACE_SECONDS = 8

local DEFAULTS = {
    version = 6,
    enabled = true,
    words = {},
    blockForeignScripts = true,
    ignoreList = {
        enabled = true,
        includeGroupGuild = true,
        players = {},
    },
    filterSources = {
        say = true,
        yell = true,
        emote = true,
        channel = true,
        whisper = true,
    },
    discoveredChannels = {},
    channelSettings = {},
    minimap = { hide = false, angle = 225 },
    activeWindow = {
        hide = true,
        width = 235,
        height = 250,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 380,
        y = 40,
    },
    window = {
        width = 900,
        height = 580,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 20,
    },
    boards = {
        clearOnLogin = true,
        collectLFG = true,
        collectTrade = true,
        hideLFG = false,
        hideTrade = false,
        maxEntries = 200,
        expiryMinutes = 15,
        cache = { lfg = {}, trade = {} },
        sources = { say = true, yell = true, emote = false, channel = true },
    },
    trainer = {
        enabled = true,
        threshold = 4,
        windowSeconds = 90,
        ignoreLFG = true,
        ignoreTrade = true,
        sources = { say = true, yell = true, emote = true, channel = true },
        pending = {},
        ignored = {},
        nextId = 1,
        importedLegacy = false,
    },
}

local PUBLIC_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
}

local WHISPER_EVENTS = { "CHAT_MSG_WHISPER" }

-- These events are only registered so CCF's player ignore list can suppress
-- ignored players outside public chat. They are never scanned for spam,
-- LFG, trade, or custom word filtering.
local IGNORE_ONLY_EVENTS = {
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_BATTLEGROUND",
    "CHAT_MSG_BATTLEGROUND_LEADER",
}

local PUBLIC_EVENT_SET = {}
local WHISPER_EVENT_SET = {}
local IGNORE_ONLY_EVENT_SET = {}

local eventIndex
for eventIndex = 1, #PUBLIC_EVENTS do
    PUBLIC_EVENT_SET[PUBLIC_EVENTS[eventIndex]] = true
end
for eventIndex = 1, #WHISPER_EVENTS do
    WHISPER_EVENT_SET[WHISPER_EVENTS[eventIndex]] = true
end
for eventIndex = 1, #IGNORE_ONLY_EVENTS do
    IGNORE_ONLY_EVENT_SET[IGNORE_ONLY_EVENTS[eventIndex]] = true
end

local STOP_WORDS = {
    ["a"] = true, ["an"] = true, ["and"] = true, ["are"] = true,
    ["at"] = true, ["for"] = true, ["from"] = true, ["in"] = true,
    ["is"] = true, ["me"] = true, ["need"] = true, ["now"] = true,
    ["of"] = true, ["on"] = true, ["or"] = true, ["please"] = true,
    ["pm"] = true, ["pst"] = true, ["the"] = true, ["to"] = true,
    ["with"] = true, ["whisper"] = true, ["lfm"] = true,
    ["lfg"] = true, ["lf"] = true, ["group"] = true, ["raid"] = true,
    ["tank"] = true, ["heal"] = true, ["healer"] = true, ["dps"] = true,
}

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    local key, child
    for key, child in pairs(value) do result[key] = DeepCopy(child) end
    return result
end

local function MergeDefaults(target, defaults)
    local key, value
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = DeepCopy(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

local function ContainsPlain(text, phrase)
    return string.find(text or "", phrase or "", 1, true) ~= nil
end

function CCF:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. tostring(message))
    end
end

function CCF:Trim(text)
    if not text then return "" end
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function CCF:Lower(text) return string.lower(text or "") end

function CCF:CountTableEntries(tbl)
    local count, key = 0, nil
    for key in pairs(tbl or {}) do count = count + 1 end
    return count
end

function CCF:RegisterReady(callback)
    if self.ready then callback() else table.insert(self.readyCallbacks, callback) end
end

function CCF:RegisterCallback(eventName, callback)
    if type(callback) ~= "function" then return end
    self.callbacks[eventName] = self.callbacks[eventName] or {}
    table.insert(self.callbacks[eventName], callback)
end

function CCF:Fire(eventName, ...)
    local list = self.callbacks[eventName]
    if not list then return end
    local index
    for index = 1, #list do
        local okay, errorMessage = pcall(list[index], ...)
        if not okay then self:Print("Callback error: " .. tostring(errorMessage)) end
    end
end

function CCF:BuildActivityIndex()
    self.activityById = {}
    self.activityOrder = {}
    local db = self.ActivityDB or {}
    local lists = { db.instances or {}, db.bosses or {} }
    local listIndex, index
    for listIndex = 1, #lists do
        for index = 1, #lists[listIndex] do
            local activity = lists[listIndex][index]
            self.activityById[activity.id] = activity
            table.insert(self.activityOrder, activity.id)
        end
    end
end

function CCF:InitializeDatabase()
    if type(CustomChatFilterDB) ~= "table" then CustomChatFilterDB = {} end
    local oldVersion = tonumber(CustomChatFilterDB.version) or 0
    MergeDefaults(CustomChatFilterDB, DEFAULTS)

    if CustomChatFilterDB.filterWhispers ~= nil and oldVersion < 3 then
        CustomChatFilterDB.filterSources.whisper =
            CustomChatFilterDB.filterWhispers and true or false
    end
    if oldVersion < 3 and CustomChatFilterDB.trainer.threshold == 3 then
        CustomChatFilterDB.trainer.threshold = 4
    end

    CustomChatFilterDB.version = 6
    self.db = CustomChatFilterDB

    if type(self.db.boards.cache) ~= "table" then
        self.db.boards.cache = { lfg = {}, trade = {} }
    end
    if type(self.db.boards.cache.lfg) ~= "table" then
        self.db.boards.cache.lfg = {}
    end
    if type(self.db.boards.cache.trade) ~= "table" then
        self.db.boards.cache.trade = {}
    end
    self.boards = self.db.boards.cache
    self:PruneBoard("lfg")
    self:PruneBoard("trade")

    local earliest = nil
    local lastUpdated = { lfg = nil, trade = nil }
    local categories = { "lfg", "trade" }
    local categoryIndex, entryIndex

    for categoryIndex = 1, #categories do
        local category = categories[categoryIndex]
        local board = self.boards[category]

        for entryIndex = 1, #board do
            local entry = board[entryIndex]
            local firstSeen = entry.firstSeen or entry.lastSeen
            local lastSeen = entry.lastSeen or entry.firstSeen

            if firstSeen and (not earliest or firstSeen < earliest) then
                earliest = firstSeen
            end
            if lastSeen and (not lastUpdated[category] or lastSeen > lastUpdated[category]) then
                lastUpdated[category] = lastSeen
            end
        end
    end

    self.boardSession = {
        startedAt = earliest or time(),
        lastUpdated = lastUpdated,
    }

    local legacy = CustomChatFilterSpamTrainerDB
    local trainer = self.db.trainer
    if not trainer.importedLegacy and type(legacy) == "table" then
        if type(legacy.windowSeconds) == "number" then
            trainer.windowSeconds = legacy.windowSeconds
        end
        if type(legacy.nextId) == "number" and legacy.nextId > trainer.nextId then
            trainer.nextId = legacy.nextId
        end
        if type(legacy.ignored) == "table" then
            local key, value
            for key, value in pairs(legacy.ignored) do
                if value then trainer.ignored[key] = true end
            end
        end
        if type(legacy.pending) == "table" then
            local index
            for index = 1, #legacy.pending do
                local old = legacy.pending[index]
                if type(old) == "table" and old.phrase and old.fingerprint then
                    table.insert(trainer.pending, DeepCopy(old))
                end
            end
        end
        trainer.importedLegacy = true
    end

    self:BuildActivityIndex()
end

function CCF:NormalizeWord(text) return self:Lower(self:Trim(text)) end

function CCF:FindWordIndex(word)
    local wanted = self:NormalizeWord(word)
    if wanted == "" then return nil end
    local index
    for index = 1, #self.db.words do
        if self:NormalizeWord(self.db.words[index]) == wanted then return index end
    end
    return nil
end

function CCF:AddWord(word)
    word = self:Trim(word)
    if word == "" then return false, "Enter a word or phrase." end
    if self:FindWordIndex(word) then
        return false, '"' .. word .. '" is already in the filter.'
    end
    table.insert(self.db.words, word)
    self:Fire("WORDS_UPDATED")
    return true, 'Added: "' .. word .. '"'
end

function CCF:RemoveWord(value)
    value = self:Trim(value)
    if value == "" then return false, "Enter a list number or exact phrase." end
    local numericIndex = tonumber(value)
    local index
    if numericIndex and numericIndex == math.floor(numericIndex) then
        index = numericIndex
    else
        index = self:FindWordIndex(value)
    end
    if not index or not self.db.words[index] then
        return false, "No matching filter entry was found."
    end
    local removed = table.remove(self.db.words, index)
    self:Fire("WORDS_UPDATED")
    return true, 'Removed: "' .. removed .. '"'
end

function CCF:StripWoWFormatting(text)
    text = text or ""
    text = string.gsub(text, "|H.-|h(.-)|h", "%1")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "|T.-|t", " ")
    return text
end

function CCF:CleanPlayerName(name)
    local value = self:Trim(self:StripWoWFormatting(name or ""))
    value = string.gsub(value, "^%[", "")
    value = string.gsub(value, "%]$", "")
    value = string.match(value, "^(%S+)") or value

    -- 3.3.5a normally supplies a bare character name. Some custom servers or
    -- backported chat addons append "-Realm", so normalize that form too.
    local bare = string.match(value, "^([^%-]+)")
    if bare and bare ~= "" then value = bare end

    return self:Trim(value)
end

function CCF:NormalizePlayerName(name)
    return self:Lower(self:CleanPlayerName(name))
end

function CCF:GetIgnoredPlayers()
    local result = {}
    local key, data

    for key, data in pairs(self.db.ignoreList.players or {}) do
        local displayName = key
        local added = 0
        local source = "unknown"

        if type(data) == "table" then
            displayName = data.name or key
            added = data.added or 0
            source = data.source or "unknown"
        elseif type(data) == "string" then
            displayName = data
        end

        table.insert(result, {
            key = key,
            name = displayName,
            added = added,
            source = source,
        })
    end

    table.sort(result, function(a, b)
        return self:Lower(a.name or "") < self:Lower(b.name or "")
    end)

    return result
end

function CCF:IsPlayerIgnored(name)
    if not self.db.ignoreList.enabled then return false end
    local key = self:NormalizePlayerName(name)
    if key == "" then return false end
    return self.db.ignoreList.players[key] ~= nil
end

function CCF:RemovePlayerFromBoards(name)
    local key = self:NormalizePlayerName(name)
    if key == "" then return end

    local categories = { "lfg", "trade" }
    local categoryIndex

    for categoryIndex = 1, #categories do
        local category = categories[categoryIndex]
        local board = self.boards[category]
        local index = #board
        local changed = false

        while index >= 1 do
            if self:NormalizePlayerName(board[index].author) == key then
                table.remove(board, index)
                changed = true
            end
            index = index - 1
        end

        if changed then self:Fire("BOARD_UPDATED", category) end
    end
end

function CCF:AddIgnoredPlayer(name, source)
    local displayName = self:CleanPlayerName(name)
    local key = self:NormalizePlayerName(displayName)

    if key == "" then
        return false, "Enter a player name."
    end

    if self.playerName and key == self:NormalizePlayerName(self.playerName) then
        return false, "You cannot add your own character to the CCF ignore list."
    end

    if self.db.ignoreList.players[key] then
        return false, displayName .. " is already ignored."
    end

    self.db.ignoreList.players[key] = {
        name = displayName,
        added = time(),
        source = source or "manual",
    }

    self:RemovePlayerFromBoards(displayName)
    self:Fire("IGNORES_UPDATED")
    return true, "Ignored player: " .. displayName
end

function CCF:RemoveIgnoredPlayer(value)
    value = self:Trim(value)
    if value == "" then
        return false, "Enter a list number or exact player name."
    end

    local key
    local number = tonumber(value)

    if number and number == math.floor(number) then
        local players = self:GetIgnoredPlayers()
        local item = players[number]
        if item then key = item.key end
    else
        key = self:NormalizePlayerName(value)
    end

    if not key or not self.db.ignoreList.players[key] then
        return false, "No matching ignored player was found."
    end

    local data = self.db.ignoreList.players[key]
    local displayName = type(data) == "table" and (data.name or key) or tostring(data)
    self.db.ignoreList.players[key] = nil
    self:Fire("IGNORES_UPDATED")
    return true, "Removed from CCF ignore list: " .. displayName
end

function CCF:ListIgnoredPlayers()
    local players = self:GetIgnoredPlayers()

    if #players == 0 then
        self:Print("The CCF player ignore list is empty.")
        return
    end

    self:Print("Ignored players:")
    local index
    for index = 1, #players do
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffaaaaaa%02d.|r %s", index, players[index].name)
        )
    end
end

function CCF:IgnoreSuggestionAuthors(entry)
    local authors = entry and entry.authors or {}
    local added = 0
    local index

    for index = 1, #authors do
        local success = self:AddIgnoredPlayer(authors[index], "spam trainer")
        if success then added = added + 1 end
    end

    return added
end

function CCF:NormalizeSearchText(message)
    local text = self:Lower(self:StripWoWFormatting(message))
    text = string.gsub(text, "[^%w%s]", " ")
    text = string.gsub(text, "%s+", " ")
    return self:Trim(text)
end

function CCF:MakeFingerprint(message)
    return string.gsub(self:NormalizeSearchText(message), "%d+", "#")
end

function CCF:Tokenize(message)
    local text = self:NormalizeSearchText(message)
    local words, set = {}, {}
    local word
    for word in string.gmatch(text, "%S+") do
        table.insert(words, word)
        set[word] = true
    end
    return words, set, text
end

function CCF:NormalizeChannelKey(name)
    local value = self:Lower(self:Trim(name or ""))
    value = string.gsub(value, "^%d+%.%s*", "")
    value = string.gsub(value, "%s+", " ")
    return value
end

function CCF:ResolveChannelName(channelName, channelBaseName)
    local name = self:Trim(channelBaseName or "")
    if name == "" then
        name = self:Trim(channelName or "")
        name = string.gsub(name, "^%d+%.%s*", "")
        local builtIn = string.match(name, "^(General)%s+%-")
            or string.match(name, "^(Trade)%s+%-")
            or string.match(name, "^(LocalDefense)%s+%-")
        if builtIn then name = builtIn end
    end
    if name == "" then name = "Unknown Channel" end
    return name, self:NormalizeChannelKey(name)
end

function CCF:DiscoverChannel(displayName, key)
    if not key or key == "" then return end
    local isNew = self.db.discoveredChannels[key] == nil
    self.db.discoveredChannels[key] = self.db.discoveredChannels[key] or {}
    self.db.discoveredChannels[key].name = displayName
    self.db.discoveredChannels[key].lastSeen = time()

    if type(self.db.channelSettings[key]) ~= "table" then
        self.db.channelSettings[key] = { filter = true, trainer = true, boards = true }
        isNew = true
    else
        if self.db.channelSettings[key].filter == nil then self.db.channelSettings[key].filter = true end
        if self.db.channelSettings[key].trainer == nil then self.db.channelSettings[key].trainer = true end
        if self.db.channelSettings[key].boards == nil then self.db.channelSettings[key].boards = true end
    end
    if isNew then self:Fire("CHANNELS_UPDATED") end
end

function CCF:GetChannelSetting(channelKey, field)
    if not channelKey or channelKey == "" then return true end
    local settings = self.db.channelSettings[channelKey]
    if not settings or settings[field] == nil then return true end
    return settings[field] and true or false
end

function CCF:SetChannelSetting(channelKey, field, value)
    if not channelKey or channelKey == "" then return end
    self.db.channelSettings[channelKey] = self.db.channelSettings[channelKey]
        or { filter = true, trainer = true, boards = true }
    self.db.channelSettings[channelKey][field] = value and true or false
    self:Fire("CHANNELS_UPDATED")
end

function CCF:GetDiscoveredChannelList()
    local result = {}
    local key, data
    for key, data in pairs(self.db.discoveredChannels or {}) do
        table.insert(result, {
            key = key,
            name = (data and data.name) or key,
            lastSeen = (data and data.lastSeen) or 0,
        })
    end
    table.sort(result, function(a, b)
        if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
        return a.name < b.name
    end)
    return result
end

function CCF:EventSourceKey(event)
    if event == "CHAT_MSG_SAY" then return "say"
    elseif event == "CHAT_MSG_YELL" then return "yell"
    elseif event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then return "emote"
    elseif event == "CHAT_MSG_CHANNEL" then return "channel"
    elseif event == "CHAT_MSG_WHISPER" then return "whisper" end
    return nil
end

function CCF:ShouldFilterSource(event, channelKey)
    local key = self:EventSourceKey(event)
    if not key or not self.db.filterSources[key] then return false end
    if key == "channel" then return self:GetChannelSetting(channelKey, "filter") end
    return true
end

function CCF:ShouldTrainSource(event, channelKey)
    local key = self:EventSourceKey(event)
    if not key or key == "whisper" or not self.db.trainer.sources[key] then return false end
    if key == "channel" then return self:GetChannelSetting(channelKey, "trainer") end
    return true
end

function CCF:ShouldScanBoards(event, channelKey)
    local key = self:EventSourceKey(event)
    if not key or key == "whisper" or not self.db.boards.sources[key] then return false end
    if key == "channel" then return self:GetChannelSetting(channelKey, "boards") end
    return true
end

local function AliasMatches(alias, tokenSet, normalizedText, uppercaseTokens)
    alias = string.lower(alias or "")
    alias = string.gsub(alias, "[^%w%s]", " ")
    alias = string.gsub(alias, "%s+", " ")
    alias = string.gsub(alias, "^%s*(.-)%s*$", "%1")
    if alias == "" then return false end
    if string.find(alias, " ", 1, true) then
        return ContainsPlain(" " .. normalizedText .. " ", " " .. alias .. " ")
    end

    -- Two-letter instance abbreviations are very collision-prone in normal
    -- language (AN, UP, OK, etc.). Require those shortcuts to be uppercase in
    -- the original message; full names and 3+ letter shortcuts remain
    -- case-insensitive.
    if string.len(alias) <= 2 then
        return tokenSet[alias] and uppercaseTokens and uppercaseTokens[alias]
    end

    return tokenSet[alias] and true or false
end

function CCF:DetectActivities(message)
    local words, tokenSet, normalizedText = self:Tokenize(message)
    local uppercaseTokens = {}
    local raw
    for raw in string.gmatch(self:StripWoWFormatting(message or ""), "%S+") do
        local clean = string.gsub(raw, "[^%w]", "")
        if string.len(clean) > 0 and string.len(clean) <= 2
            and clean == string.upper(clean) and clean ~= string.lower(clean) then
            uppercaseTokens[string.lower(clean)] = true
        end
    end
    local found, foundSet = {}, {}
    local db = self.ActivityDB or {}
    local instances, bosses = db.instances or {}, db.bosses or {}
    local index, aliasIndex

    for index = 1, #instances do
        local activity = instances[index]
        for aliasIndex = 1, #(activity.aliases or {}) do
            if AliasMatches(activity.aliases[aliasIndex], tokenSet, normalizedText, uppercaseTokens) then
                foundSet[activity.id] = true
                break
            end
        end
    end

    local specificId, parentIds
    for specificId, parentIds in pairs(db.suppress or {}) do
        if foundSet[specificId] then
            local parentIndex
            for parentIndex = 1, #parentIds do foundSet[parentIds[parentIndex]] = nil end
        end
    end

    for index = 1, #bosses do
        local activity = bosses[index]
        if foundSet[activity.parent] or activity.standalone then
            for aliasIndex = 1, #(activity.aliases or {}) do
                if AliasMatches(activity.aliases[aliasIndex], tokenSet, normalizedText, uppercaseTokens) then
                    foundSet[activity.id] = true
                    break
                end
            end
        end
    end

    local id
    for id in pairs(foundSet) do table.insert(found, id) end
    table.sort(found, function(a, b)
        local aa, bb = self.activityById[a], self.activityById[b]
        if not aa or not bb then return a < b end
        local order = { Dungeon = 1, Raid = 2, ["World Boss"] = 3, Boss = 4 }
        local ao, bo = order[aa.kind] or 9, order[bb.kind] or 9
        if ao ~= bo then return ao < bo end
        return aa.name < bb.name
    end)
    return found, foundSet
end

function CCF:ClassifyMessage(message, activities, channelKey)
    local words, set, text = self:Tokenize(message)
    if #words == 0 then return nil, nil end

    local lookingForMore = set.lfm
    local wordIndex
    for wordIndex = 1, #words do
        if string.match(words[wordIndex], "^lf[1-4]m$") then
            lookingForMore = true
            break
        end
    end

    local profession = set.enchanter or set.enchanting or set.blacksmith
        or set.blacksmithing or set.jewelcrafter or set.jewelcrafting
        or set.tailor or set.tailoring or set.alchemist or set.alchemy
        or set.inscription or set.scribe or set.engineer or set.engineering
        or set.leatherworker or set.leatherworking

    local tradeType
    if set.wts or set.selling or ContainsPlain(text, "want to sell")
        or ContainsPlain(text, "looking to sell") or ContainsPlain(text, "for sale") then
        tradeType = "WTS"
    elseif set.wtb or set.buying or ContainsPlain(text, "want to buy")
        or ContainsPlain(text, "looking to buy") then
        tradeType = "WTB"
    elseif set.wtt or ContainsPlain(text, "want to trade") then
        tradeType = "WTT"
    elseif set.lf and profession then
        tradeType = "SERVICE"
    end
    if tradeType then return "trade", tradeType end

    local lfg = set.lfg or lookingForMore or ContainsPlain(text, "looking for group")
        or ContainsPlain(text, "looking for more")
        or ContainsPlain(text, "looking for members")
        or ContainsPlain(text, "need tank") or ContainsPlain(text, "need healer")
        or ContainsPlain(text, "need heal") or ContainsPlain(text, "need dps")
        or ContainsPlain(text, "need all roles")
        or ContainsPlain(text, "forming group") or ContainsPlain(text, "forming raid")

    if not lfg and activities and #activities > 0 then
        lfg = set.need or set.anyone or set.inv or set.invite or set.tank
            or set.heal or set.healer or set.dps or set.run or set.group
            or set.raid or set.spots or set.spot or set.last or set.forming
        if not lfg and channelKey then
            lfg = ContainsPlain(channelKey, "lookingforgroup")
                or ContainsPlain(channelKey, "looking for group")
                or channelKey == "lfg"
        end
    end
    if lfg then return "lfg", nil end
    return nil, nil
end

function CCF:ParseLFGMetadata(message)
    local words, set, text = self:Tokenize(message)
    local meta = { roles = {}, size = nil, difficulty = nil }
    if set.tank or set.tanks then meta.roles.tank = true end
    if set.heal or set.healer or set.healers then meta.roles.healer = true end
    if set.dps or set.dd then meta.roles.dps = true end
    if set["25"] or ContainsPlain(text, "25 man") or ContainsPlain(text, "25man") then
        meta.size = 25
    elseif set["10"] or ContainsPlain(text, "10 man") or ContainsPlain(text, "10man") then
        meta.size = 10
    end
    if set.hc or set.heroic or set.hm or set.hardmode then
        meta.difficulty = "Heroic"
    elseif set.nm or set.normal then
        meta.difficulty = "Normal"
    end
    return meta
end

function CCF:EnsureBoardSession()
    if type(self.boardSession) ~= "table" then
        self.boardSession = {}
    end

    if type(self.boardSession.startedAt) ~= "number" then
        self.boardSession.startedAt = time()
    end

    if type(self.boardSession.lastUpdated) ~= "table" then
        self.boardSession.lastUpdated = { lfg = nil, trade = nil }
    end
end

function CCF:GetBoardSessionInfo(category)
    self:EnsureBoardSession()
    return self.boardSession.startedAt, self.boardSession.lastUpdated[category]
end

function CCF:ClearAllBoards(startNewSession, reason)
    self.boards.lfg = {}
    self.boards.trade = {}
    self:EnsureBoardSession()

    if startNewSession then
        self.boardSession.startedAt = time()
    end

    self.boardSession.lastUpdated = { lfg = nil, trade = nil }
    self:Fire("BOARD_SESSION_RESET", reason or "manual")
    self:Fire("BOARD_UPDATED", "lfg")
    self:Fire("BOARD_UPDATED", "trade")
end

function CCF:PruneBoard(category)
    local board = self.boards[category]
    if not board then return end
    local now = time()
    local expiry = (self.db.boards.expiryMinutes or 15) * 60
    local index = #board
    while index >= 1 do
        if now - (board[index].lastSeen or now) > expiry then table.remove(board, index) end
        index = index - 1
    end
    while #board > (self.db.boards.maxEntries or 200) do table.remove(board) end
end

function CCF:AddBoardEntry(category, message, author, channelName, activities, activitySet, tradeType)
    if category == "lfg" and not self.db.boards.collectLFG then return end
    if category == "trade" and not self.db.boards.collectTrade then return end
    local board = self.boards[category]
    if not board then return end
    self:PruneBoard(category)

    local fingerprint = self:MakeFingerprint(message)
    local key = self:Lower(author or "") .. "|" .. fingerprint
    local now = time()
    local metadata = category == "lfg" and self:ParseLFGMetadata(message) or nil
    local index
    for index = 1, #board do
        local entry = board[index]
        if entry.key == key then
            entry.message = self:StripWoWFormatting(message)
            entry.channel = channelName or ""
            entry.lastSeen = now
            entry.count = (entry.count or 1) + 1
            entry.activities = activities or {}
            entry.activitySet = activitySet or {}
            entry.tradeType = tradeType
            entry.meta = metadata
            self:EnsureBoardSession()
            self.boardSession.lastUpdated[category] = now
            if index > 1 then table.remove(board, index); table.insert(board, 1, entry) end
            self:Fire("BOARD_UPDATED", category)
            return
        end
    end

    table.insert(board, 1, {
        key = key,
        fingerprint = fingerprint,
        author = author or "?",
        message = self:StripWoWFormatting(message),
        channel = channelName or "",
        firstSeen = now,
        lastSeen = now,
        count = 1,
        activities = activities or {},
        activitySet = activitySet or {},
        tradeType = tradeType,
        meta = metadata,
    })
    while #board > (self.db.boards.maxEntries or 200) do table.remove(board) end
    self:EnsureBoardSession()
    self.boardSession.lastUpdated[category] = now
    self:Fire("BOARD_UPDATED", category)
end

function CCF:ClearBoard(category)
    if self.boards[category] then
        self.boards[category] = {}
        self:EnsureBoardSession()
        self.boardSession.lastUpdated[category] = nil
        self:Fire("BOARD_UPDATED", category)
    end
end

function CCF:GetActiveActivities()
    self:PruneBoard("lfg")

    local stats = {}
    local board = self.boards.lfg
    local index, activityIndex

    for index = 1, #board do
        local entry = board[index]
        for activityIndex = 1, #(entry.activities or {}) do
            local id = entry.activities[activityIndex]
            local item = stats[id]

            if not item then
                item = {
                    count = 0,
                    firstSeen = entry.firstSeen or entry.lastSeen or time(),
                    lastSeen = entry.lastSeen or entry.firstSeen or time(),
                }
                stats[id] = item
            end

            item.count = item.count + 1
            item.firstSeen = math.min(item.firstSeen, entry.firstSeen or item.firstSeen)
            item.lastSeen = math.max(item.lastSeen, entry.lastSeen or item.lastSeen)
        end
    end

    local result = {}
    local id, item
    local now = time()

    for id, item in pairs(stats) do
        local activity = self.activityById[id]
        if activity then
            table.insert(result, {
                id = id,
                count = item.count,
                firstSeen = item.firstSeen,
                lastSeen = item.lastSeen,
                isNew = now - item.firstSeen <= 30,
                activity = activity,
            })
        end
    end

    table.sort(result, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end

        local order = { Dungeon = 1, Raid = 2, ["World Boss"] = 3, Boss = 4 }
        local ao = order[a.activity.kind] or 9
        local bo = order[b.activity.kind] or 9

        if ao ~= bo then
            return ao < bo
        end

        return a.activity.name < b.activity.name
    end)

    return result
end

local function ReadUTF8CodePoint(text, index)
    local b1 = string.byte(text, index)
    if not b1 then return nil, index + 1 end
    if b1 < 0x80 then return b1, index + 1 end
    local b2 = string.byte(text, index + 1)
    if b1 >= 0xC2 and b1 <= 0xDF and b2 and b2 >= 0x80 and b2 <= 0xBF then
        return (b1 - 0xC0) * 0x40 + (b2 - 0x80), index + 2
    end
    local b3 = string.byte(text, index + 2)
    if b1 >= 0xE0 and b1 <= 0xEF and b2 and b2 >= 0x80 and b2 <= 0xBF
        and b3 and b3 >= 0x80 and b3 <= 0xBF then
        return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), index + 3
    end
    local b4 = string.byte(text, index + 3)
    if b1 >= 0xF0 and b1 <= 0xF4 and b2 and b2 >= 0x80 and b2 <= 0xBF
        and b3 and b3 >= 0x80 and b3 <= 0xBF and b4 and b4 >= 0x80 and b4 <= 0xBF then
        return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000
            + (b3 - 0x80) * 0x40 + (b4 - 0x80), index + 4
    end
    return nil, index + 1
end

local function InRange(codePoint, first, last) return codePoint >= first and codePoint <= last end

local function IsForeignScript(codePoint)
    if not codePoint then return false end
    return InRange(codePoint, 0x0370, 0x03FF) or InRange(codePoint, 0x1F00, 0x1FFF)
        or InRange(codePoint, 0x0400, 0x052F) or InRange(codePoint, 0x2DE0, 0x2DFF)
        or InRange(codePoint, 0xA640, 0xA69F) or InRange(codePoint, 0x0530, 0x058F)
        or InRange(codePoint, 0x0590, 0x05FF) or InRange(codePoint, 0x0600, 0x06FF)
        or InRange(codePoint, 0x0750, 0x077F) or InRange(codePoint, 0x08A0, 0x08FF)
        or InRange(codePoint, 0xFB50, 0xFDFF) or InRange(codePoint, 0xFE70, 0xFEFF)
        or InRange(codePoint, 0x0900, 0x0DFF) or InRange(codePoint, 0x0E00, 0x0EFF)
        or InRange(codePoint, 0x10A0, 0x10FF) or InRange(codePoint, 0x2E80, 0x303F)
        or InRange(codePoint, 0x3040, 0x30FF) or InRange(codePoint, 0x31F0, 0x31FF)
        or InRange(codePoint, 0x3400, 0x4DBF) or InRange(codePoint, 0x4E00, 0x9FFF)
        or InRange(codePoint, 0xF900, 0xFAFF) or InRange(codePoint, 0x1100, 0x11FF)
        or InRange(codePoint, 0x3130, 0x318F) or InRange(codePoint, 0xAC00, 0xD7AF)
end

function CCF:ContainsForeignScript(text)
    local index, length = 1, string.len(text or "")
    while index <= length do
        local codePoint
        codePoint, index = ReadUTF8CodePoint(text, index)
        if IsForeignScript(codePoint) then return true end
    end
    return false
end

function CCF:MatchCustomFilter(message)
    if self.db.blockForeignScripts and self:ContainsForeignScript(message) then
        return true, "non-Latin writing"
    end
    local lowered = self:Lower(message)
    local index
    for index = 1, #self.db.words do
        local word = self:NormalizeWord(self.db.words[index])
        if word ~= "" and string.find(lowered, word, 1, true) then
            return true, self.db.words[index]
        end
    end
    return false, nil
end

function CCF:ExtractDomain(message)
    local text = self:Lower(self:StripWoWFormatting(message))
    local domain = string.match(text, "(discord%.gg/[%w%-_]+)")
    if domain then return domain end
    domain = string.match(text, "(www%.[%w%-_]+%.[%a]+)")
    if domain then return domain end
    domain = string.match(text, "([%w%-_]+%.[%a][%a]+)")
    if domain and string.len(domain) >= 6 then return domain end
    return nil
end

local function JoinWords(words, firstIndex, lastIndex)
    local result, index = {}, nil
    for index = firstIndex, lastIndex do table.insert(result, words[index]) end
    return table.concat(result, " ")
end

local function ScorePhrase(words, firstIndex, lastIndex)
    local score, meaningful, index = 0, 0, nil
    for index = firstIndex, lastIndex do
        local word, length = words[index], string.len(words[index])
        score = score + length
        if STOP_WORDS[word] then score = score - 7
        elseif length >= 4 then meaningful = meaningful + 1; score = score + 5 end
        if length <= 2 then score = score - 3 end
    end
    if lastIndex - firstIndex + 1 >= 3 then score = score + 5 end
    if meaningful == 0 then score = score - 100 end
    return score
end

function CCF:SuggestPhrase(message)
    local domain = self:ExtractDomain(message)
    if domain then return domain end
    local words = self:Tokenize(message)
    local wordCount = #words
    if wordCount == 0 then return "" end
    if wordCount <= 4 then return table.concat(words, " ") end
    local bestPhrase, bestScore, size = "", -100000, nil
    for size = 2, 5 do
        local firstIndex
        for firstIndex = 1, wordCount - size + 1 do
            local lastIndex = firstIndex + size - 1
            local score = ScorePhrase(words, firstIndex, lastIndex)
            if score > bestScore then
                bestScore = score
                bestPhrase = JoinWords(words, firstIndex, lastIndex)
            end
        end
    end
    return bestPhrase
end

function CCF:DetectInlineRepeat(message)
    local threshold = (self.db and self.db.trainer and self.db.trainer.threshold) or 4
    if threshold < 2 then threshold = 2 end

    local words = self:Tokenize(message)
    if #words < threshold then return nil, 0 end

    local bestWord, bestCount = nil, 0
    local currentWord, currentCount = nil, 0
    local index

    for index = 1, #words do
        local word = words[index]
        if word == currentWord then
            currentCount = currentCount + 1
        else
            currentWord = word
            currentCount = 1
        end

        if currentCount >= threshold and string.len(word) >= 3 and not STOP_WORDS[word] then
            if currentCount > bestCount then
                bestWord = word
                bestCount = currentCount
            end
        end
    end

    return bestWord, bestCount
end

function CCF:ObserveInlineRepeatSpam(message, author)
    local trainer = self.db.trainer
    if not trainer.enabled then return end

    local example = self:StripWoWFormatting(message)
    local word, count = self:DetectInlineRepeat(example)
    if not word or count < trainer.threshold then return end

    local fingerprint = "inline_repeat:" .. word
    if trainer.ignored[fingerprint] or self:FindPendingByFingerprint(fingerprint) then return end

    local entry = {
        count = count,
        firstSeen = time(),
        lastSeen = time(),
        authors = {},
        example = example,
        fingerprint = fingerprint,
        suggested = true,
        phrase = word,
    }

    if author and author ~= "" then
        local authorKey = self:NormalizePlayerName(author)
        if authorKey ~= "" then
            entry.authors[authorKey] = self:CleanPlayerName(author)
        end
    end

    self.recentSpam[fingerprint] = entry
    self:CreateSuggestion(entry)
end

function CCF:FindPendingById(id)
    local pending, index = self.db.trainer.pending, nil
    for index = 1, #pending do
        if pending[index].id == id then return pending[index], index end
    end
    return nil, nil
end

function CCF:FindPendingByFingerprint(fingerprint)
    local pending, index = self.db.trainer.pending, nil
    for index = 1, #pending do
        if pending[index].fingerprint == fingerprint then return pending[index], index end
    end
    return nil, nil
end

function CCF:CreateSuggestion(entry)
    local trainer = self.db.trainer
    if trainer.ignored[entry.fingerprint] or self:FindPendingByFingerprint(entry.fingerprint) then return end
    local phrase = entry.phrase or self:SuggestPhrase(entry.example)
    if phrase == "" then return end

    local authors = {}
    local authorKey, authorName
    for authorKey, authorName in pairs(entry.authors or {}) do
        if type(authorName) == "string" and authorName ~= "" then
            table.insert(authors, authorName)
        else
            table.insert(authors, authorKey)
        end
    end
    table.sort(authors, function(a, b) return self:Lower(a) < self:Lower(b) end)

    local suggestion = {
        id = trainer.nextId,
        fingerprint = entry.fingerprint,
        observationKey = entry.observationKey,
        phrase = phrase,
        example = entry.example,
        count = entry.count,
        authorCount = #authors,
        authors = authors,
        created = time(),
    }
    trainer.nextId = trainer.nextId + 1
    table.insert(trainer.pending, suggestion)
    while #trainer.pending > 50 do table.remove(trainer.pending, 1) end
    self:Print(string.format('Spam suggestion #%d: "%s" — review it from the minimap button.', suggestion.id, suggestion.phrase))
    self:Fire("TRAINER_UPDATED")
end

function CCF:PruneRecentSpam(now)
    local expiry = (self.db.trainer.windowSeconds or 90) * 2
    local fingerprint, entry
    for fingerprint, entry in pairs(self.recentSpam) do
        if now - entry.lastSeen > expiry then self.recentSpam[fingerprint] = nil end
    end
end

function CCF:ObserveSpam(message, author, category, channelKey)
    local trainer = self.db.trainer
    if not trainer.enabled then return end
    if category == "lfg" and trainer.ignoreLFG then return end
    if category == "trade" and trainer.ignoreTrade then return end

    self:ObserveInlineRepeatSpam(message, author)

    local fingerprint = self:MakeFingerprint(message)
    if fingerprint == "" or string.len(fingerprint) < 12 then return end
    local wordCount, unused = 0, nil
    for unused in string.gmatch(fingerprint, "%S+") do wordCount = wordCount + 1 end
    if wordCount < 3 or trainer.ignored[fingerprint] then return end

    -- Repetition is a sender behaviour. Do not let several players saying the
    -- same common thing add up to a single spam report.
    local authorKey = self:NormalizePlayerName(author or "")
    if authorKey == "" then return end

    local now = time()
    self:PruneRecentSpam(now)
    local observationKey = "repeat:" .. authorKey .. "\030" .. fingerprint
    local entry = self.recentSpam[observationKey]
    if not entry or now - entry.lastSeen > trainer.windowSeconds then
        entry = {
            count = 0,
            firstSeen = now,
            lastSeen = now,
            authors = {},
            channels = {},
            example = self:StripWoWFormatting(message),
            fingerprint = fingerprint,
            observationKey = observationKey,
            suggested = false,
        }
        self.recentSpam[observationKey] = entry
    end

    -- Treat quick copies to multiple channels as one posting burst. A later
    -- repeat still counts, even when it is sent to a different channel.
    local isCrossPost = entry.count > 0
        and now - entry.lastSeen <= CROSS_POST_GRACE_SECONDS
        and channelKey and channelKey ~= ""
        and not entry.channels[channelKey]
    entry.channels[channelKey or ""] = true
    entry.lastSeen = now
    if isCrossPost then return end

    entry.count = entry.count + 1
    entry.authors[authorKey] = self:CleanPlayerName(author)
    if not entry.suggested and entry.count >= trainer.threshold then
        entry.suggested = true
        self:CreateSuggestion(entry)
    end
end

function CCF:FinalizeSuggestions(checkedIds, ignoreAuthorIds)
    local pending = self.db.trainer.pending
    local added, dismissed, ignoredPlayers, index = 0, 0, 0, nil

    for index = 1, #pending do
        local entry = pending[index]

        if checkedIds and checkedIds[entry.id] then
            local success = self:AddWord(entry.phrase)
            if success then added = added + 1 end
        else
            self.db.trainer.ignored[entry.fingerprint] = true
            dismissed = dismissed + 1
        end

        if ignoreAuthorIds and ignoreAuthorIds[entry.id] then
            ignoredPlayers = ignoredPlayers + self:IgnoreSuggestionAuthors(entry)
        end

        self.recentSpam[entry.observationKey or entry.fingerprint] = nil
    end

    self.db.trainer.pending = {}
    self:Fire("TRAINER_UPDATED")
    return added, dismissed, ignoredPlayers
end

function CCF:ProcessPublicMessage(event, message, author, channelName, channelKey)
    local activities, activitySet = self:DetectActivities(message)
    local category, tradeType = self:ClassifyMessage(message, activities, channelKey)
    local boardAllowed = self:ShouldScanBoards(event, channelKey)
    if category and boardAllowed then
        self:AddBoardEntry(category, message, author, channelName, activities, activitySet, tradeType)
    end
    if self:ShouldTrainSource(event, channelKey) then
        self:ObserveSpam(message, author, category, channelKey)
    end

    local blocked = false
    if self.db.enabled and self:ShouldFilterSource(event, channelKey) then
        blocked = self:MatchCustomFilter(message)
    end
    if not blocked and boardAllowed and category == "lfg"
        and self.db.boards.collectLFG and self.db.boards.hideLFG then blocked = true end
    if not blocked and boardAllowed and category == "trade"
        and self.db.boards.collectTrade and self.db.boards.hideTrade then blocked = true end
    return blocked and true or false
end

function CCF:ChatMessageFilter(event, message, author, channelName, channelBaseName)
    if not self.ready then return false end

    if author and self.playerName
        and self:NormalizePlayerName(author) == self:NormalizePlayerName(self.playerName) then
        return false
    end

    if author and self:IsPlayerIgnored(author) then
        if PUBLIC_EVENT_SET[event] or WHISPER_EVENT_SET[event] then
            return true
        end

        if IGNORE_ONLY_EVENT_SET[event] and self.db.ignoreList.includeGroupGuild then
            return true
        end
    end

    -- Group/guild events are registered only for the player ignore list.
    if IGNORE_ONLY_EVENT_SET[event] then return false end

    local channelDisplay, channelKey = "", ""
    if event == "CHAT_MSG_CHANNEL" then
        channelDisplay, channelKey = self:ResolveChannelName(channelName, channelBaseName)
        self:DiscoverChannel(channelDisplay, channelKey)
    end

    if event == "CHAT_MSG_WHISPER" then
        if not self.db.enabled or not self:ShouldFilterSource(event, nil) then return false end
        local blocked = self:MatchCustomFilter(message or "")
        return blocked and true or false
    end

    local key = table.concat({ event or "", author or "", channelDisplay or "", message or "" }, "\031")
    local now = GetTime and GetTime() or 0
    local cached = self.dispatchCache[key]
    if cached and now - cached.time < 0.25 then return cached.blocked end

    local blocked = self:ProcessPublicMessage(event, message or "", author or "", channelDisplay, channelKey)
    self.dispatchCache[key] = { time = now, blocked = blocked and true or false }
    return blocked and true or false
end

local function ChatFilterAdapter(self, event, message, author, languageName, channelName,
    playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...)
    return CCF:ChatMessageFilter(event, message, author, channelName, channelBaseName)
end

function CCF:RegisterChatFilters()
    local index
    for index = 1, #PUBLIC_EVENTS do
        ChatFrame_AddMessageEventFilter(PUBLIC_EVENTS[index], ChatFilterAdapter)
    end
    for index = 1, #WHISPER_EVENTS do
        ChatFrame_AddMessageEventFilter(WHISPER_EVENTS[index], ChatFilterAdapter)
    end
    for index = 1, #IGNORE_ONLY_EVENTS do
        ChatFrame_AddMessageEventFilter(IGNORE_ONLY_EVENTS[index], ChatFilterAdapter)
    end
end

function CCF:ListWords()
    if #self.db.words == 0 then self:Print("The custom word list is empty."); return end
    self:Print("Filtered words and phrases:")
    local index
    for index = 1, #self.db.words do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaa%02d.|r %s", index, self.db.words[index]))
    end
end

function CCF:PrintStatus()
    self:Print(string.format(
        "enabled=%s, words=%d, ignored=%d, LFG=%d, Trade=%d, suggestions=%d, channels=%d",
        self.db.enabled and "yes" or "no", #self.db.words,
        #self:GetIgnoredPlayers(), #self.boards.lfg, #self.boards.trade,
        #self.db.trainer.pending,
        self:CountTableEntries(self.db.discoveredChannels)))
end

function CCF:PrintHelp()
    self:Print("Commands:")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf hub|r - open the Chat Hub")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf lfg|r, |cffffffff/ccf trade|r, |cffffffff/ccf trainer|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf options [filter|trainer|boards|channels|ignored]|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf add <word or phrase>|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf del <number or exact phrase>|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf list|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf ignore <player>|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf unignore <player or list number>|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf ignores|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf test <message>|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf minimap show|r or |cffffffff/ccf minimap hide|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf active|r, |cffffffff/ccf active show|r, |cffffffff/ccf active hide|r")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff/ccf status|r")
end

local function SlashCommand(input)
    input = CCF:Trim(input)
    local command, rest = string.match(input, "^(%S*)%s*(.-)$")
    command, rest = CCF:Lower(command or ""), CCF:Trim(rest or "")
    if command == "" or command == "help" then CCF:PrintHelp(); return end
    if command == "hub" then CCF:OpenPage("lfg"); return end
    if command == "lfg" or command == "trade" or command == "trainer" then CCF:OpenPage(command); return end
    if command == "options" then CCF:OpenOptions(CCF:Lower(rest)); return end
    if command == "minimap" then
        local value = CCF:Lower(rest)
        if value == "hide" or value == "off" then
            CCF.db.minimap.hide = true
            CCF:Print("Minimap button hidden. Use /ccf minimap show to restore it.")
        else
            CCF.db.minimap.hide = false
            CCF:Print("Minimap button shown.")
        end
        CCF:UpdateMinimapVisibility()
        CCF:Fire("OPTIONS_UPDATED")
        return
    end
    if command == "active" or command == "activewindow" then
        local value = CCF:Lower(rest)
        if value == "hide" or value == "off" then
            CCF.db.activeWindow.hide = true
            if CCF.HideActiveWindow then CCF:HideActiveWindow() end
            CCF:Print("Standalone active-instances window hidden.")
        elseif value == "show" or value == "on" then
            CCF.db.activeWindow.hide = false
            if CCF.ShowActiveWindow then CCF:ShowActiveWindow() end
            CCF:Print("Standalone active-instances window shown.")
        else
            CCF.db.activeWindow.hide = not CCF.db.activeWindow.hide
            if CCF.db.activeWindow.hide then
                if CCF.HideActiveWindow then CCF:HideActiveWindow() end
                CCF:Print("Standalone active-instances window hidden.")
            else
                if CCF.ShowActiveWindow then CCF:ShowActiveWindow() end
                CCF:Print("Standalone active-instances window shown.")
            end
        end
        CCF:Fire("OPTIONS_UPDATED")
        return
    end
    if command == "add" then local success, message = CCF:AddWord(rest); CCF:Print(message); return end
    if command == "del" or command == "delete" or command == "remove" then
        local success, message = CCF:RemoveWord(rest); CCF:Print(message); return
    end
    if command == "list" then CCF:ListWords(); return end
    if command == "ignore" then
        local success, message = CCF:AddIgnoredPlayer(rest, "slash command")
        CCF:Print(message)
        return
    end
    if command == "unignore" then
        local success, message = CCF:RemoveIgnoredPlayer(rest)
        CCF:Print(message)
        return
    end
    if command == "ignores" or command == "ignorelist" then
        CCF:ListIgnoredPlayers()
        return
    end
    if command == "test" then
        if rest == "" then CCF:Print("Enter a test message."); return end
        local blocked, reason = CCF:MatchCustomFilter(rest)
        local activities = CCF:DetectActivities(rest)
        local category = CCF:ClassifyMessage(rest, activities, nil)
        if blocked then CCF:Print('BLOCKED by "' .. tostring(reason) .. '"')
        else CCF:Print("Not blocked. Category: " .. tostring(category or "none") .. ", activities: " .. tostring(#activities)) end
        return
    end
    if command == "on" then CCF.db.enabled = true; CCF:Print("Custom filtering enabled."); CCF:Fire("OPTIONS_UPDATED"); return end
    if command == "off" then CCF.db.enabled = false; CCF:Print("Custom filtering disabled."); CCF:Fire("OPTIONS_UPDATED"); return end
    if command == "status" then CCF:PrintStatus(); return end
    CCF:Print('Unknown command "' .. command .. '". Use /ccf help')
end

SLASH_CUSTOMCHATFILTER1 = "/ccf"
SLASH_CUSTOMCHATFILTER2 = "/chatfilter"
SlashCmdList["CUSTOMCHATFILTER"] = SlashCommand

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "CustomChatFilter" then
        CCF:InitializeDatabase()
        CCF:RegisterChatFilters()
        CCF.ready = true
        local callbacks = CCF.readyCallbacks
        CCF.readyCallbacks = {}
        local index
        for index = 1, #callbacks do
            local okay, errorMessage = pcall(callbacks[index])
            if not okay then CCF:Print("Initialization error: " .. tostring(errorMessage)) end
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        CCF.playerName = UnitName("player")

        if CCF.db.boards.clearOnLogin then
            CCF:ClearAllBoards(true, "login")
        else
            CCF:EnsureBoardSession()
        end

        CCF:PrintStatus()
    end
end)
