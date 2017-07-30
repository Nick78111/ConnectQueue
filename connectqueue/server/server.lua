local Config = {}
----------------------------------------------------------------------------------------------------------------------
-- Priority list can be any identifier. (hex steamid, steamid32, ip) Integer = power over other priorities
Config.Priority = {
    ["STEAM_0:1:#######"] = 50,
    ["steam:110000######"] = 25,
    ["ip:127.0.0.0"] = 85
}

-- easy localization
Config.Language = {
    joining = "Joining...",
    connecting = "Connecting...",
    err = "Error: Couldn't retrieve any of your id's, try restarting.",
    pos = "You are %d/%d in queue"
}
-----------------------------------------------------------------------------------------------------------------------

local Queue = {}
Queue.QueueList = {}
Queue.PlayerList = {}
Queue.PlayerCount = 0
Queue.Priority = {}
Queue.Connecting = {}

local debug = false
local displayQueue = false
local initHostName = false
local maxPlayers = 30

local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local print = print
local string_sub = string.sub
local string_format = string.format
local string_lower = string.lower
local math_abs = math.abs
local math_floor = math.floor
local os_time = os.time
local table_insert = table.insert
local table_remove = table.remove

for k,v in pairs(Config.Priority) do
    Queue.Priority[string_lower(k)] = v
end

-- converts hex steamid to SteamID 32
function Queue:HexIdToSteamId(hexId)
    local cid = math_floor(tonumber(string_sub(hexId, 7), 16))
	local steam64 = math_floor(tonumber(string_sub( cid, 2)))
	local a = steam64 % 2 == 0 and 0 or 1
	local b = math_floor(math_abs(6561197960265728 - steam64 - a) / 2)
	local sid = "steam_0:"..a..":"..(a == 1 and b -1 or b)
    return sid
end

function Queue:DebugPrint(msg)
    if debug then
        msg = "QUEUE: " .. tostring(msg)
        print(msg)
    end
end

function Queue:IsInQueue(ids, rtnTbl, bySource)
    for k,v in ipairs(self.QueueList) do
        local inQueue = false

        if not bySource then
            for i,j in ipairs(v.ids) do
                if inQueue then break end

                for q,e in ipairs(ids) do
                    if e == j then inQueue = true break end
                end
            end
        else
            inQueue = ids == v.source
        end

        if inQueue then
            if rtnTbl then
                return k, self.QueueList[k]
            end

            return true
        end
    end

    return false
end

function Queue:IsPriority(ids)
    for k,v in ipairs(ids) do
        v = string_lower(v)

        if string_sub(v, 1, 5) == "steam" and not self.Priority[v] then
            local steamid = self:HexIdToSteamId(v)
            if self.Priority[steamid] then return self.Priority[steamid] ~= nil and self.Priority[steamid] or false end
        end

        if self.Priority[v] then return self.Priority[v] ~= nil and self.Priority[v] or false end
    end
end

function Queue:AddToQueue(ids, connectTime, name, src)
    if self:IsInQueue(ids) then return end

    local tmp = {
        source = src,
        ids = ids,
        name = name,
        firstconnect = connectTime,
        priority = self:IsPriority(ids) or (src == "debug" and math.random(0, 15))
    }

    local _pos = false
    local queueCount = self:GetSize() + 1

    for k,v in ipairs(self.QueueList) do
        if tmp.priority then
            if not v.priority then
                _pos = k
            else
                if tmp.priority > v.priority then
                    _pos = k
                end
            end

            if _pos then
                self:DebugPrint(string_format("%s[%s] was prioritized and placed %d/%d in queue", tmp.name, ids[1], _pos, queueCount))
                break
            end
        end
    end

    if not _pos then
        _pos = self:GetSize() + 1
        self:DebugPrint(string_format("%s[%s] was placed %d/%d in queue", tmp.name, ids[1], _pos, queueCount))
    end

    table_insert(self.QueueList, _pos, tmp)
end

function Queue:RemoveFromQueue(ids, bySource)
    if self:IsInQueue(ids, false, bySource) then
        local pos, data = self:IsInQueue(ids, true, bySource)
        table_remove(self.QueueList, pos)
    end
end

function Queue:GetSize()
    return #self.QueueList
end

function Queue:ConnectingSize()
    return #self.Connecting
end

function Queue:IsInConnecting(ids, bySource)
    for k,v in ipairs(self.Connecting) do
        local _type = bySource and v.source or v.ids[1]
        return bySource and _type == ids or _type == ids[1]
    end

    return false
end

function Queue:AddToConnecting(ids)
    if self:ConnectingSize() >= 5 then return false end
    if ids[1] == "debug" then
        table_insert(self.Connecting, {source = ids[1], ids = ids, name = ids[1], firstconnect = ids[1], priority = ids[1]})
        return true
    end

    if self:IsInConnecting(ids) then self:RemoveFromConnecting(ids) end

    local pos, data = self:IsInQueue(ids, true)
    if not pos or pos > 1 then return false end
    
    table_insert(self.Connecting, data)
    return true
end

function Queue:RemoveFromConnecting(ids, bySource)
    for k,v in ipairs(self.Connecting) do
        local inConnecting = false

        if not bySource then
            for i,j in ipairs(v.ids) do
                if inConnecting then break end

                for q,e in ipairs(ids) do
                    if e == j then inConnecting = true break end
                end
            end
        else
            inConnecting = ids == v.source
        end

        if inConnecting then
            table_remove(self.Connecting, k)
            return true
        end
    end

    return false
end

function Queue:GetIds(src)
    local ids = GetPlayerIdentifiers(src)
    ids = (ids and ids[1]) and ids or {"ip:" .. GetPlayerEP(src)}
    ids = ids ~= nil and ids or false
    return ids
end

function Queue:AddPriority(id, power)
    if not id then return false end

    if type(id) == "table" then
        for k, v in pairs(id) do
            if k and type(k) == "string" and v and type(v) == "number" then
                self.Priority[k] = string_lower(v)
            else
                self:DebugPrint("Error adding a priority id, invalid data passed")
                return false
            end
        end

        return true
    end

    power = (power and type(power) == "number") and power or 10
    self.Priority[string_lower(id)] = power

    return true
end

function Queue:RemovePriority(id)
    if not id then return false end
    self.Priority[id] = nil
    return true
end

-- export
function AddPriority(id, power)
    return Queue:AddPriority(id, power)
end

-- export
function RemovePriority(id)
    return Queue:RemovePriority(id)
end

local function playerConnect(name, setKickReason, deferrals)
    maxPlayers = GetConvarInt("sv_maxclients", 30)
    debug = GetConvar("sv_debugqueue", "true") == "true" and true or false
    displayQueue = GetConvar("sv_displayqueue", "true") == "true" and true or false
    initHostName = not initHostName and GetConvar("sv_hostname") or initHostName

    local src = source
    local ids = Queue:GetIds(src)
    local connectTime = os_time()

    deferrals.defer()

    local function updateDeferral(msg, letJoin)
        if letJoin then
            local added = Queue:AddToConnecting(ids)
            if not added then
                Queue:RemoveFromQueue(ids)
                Queue:RemoveFromConnecting(ids)
                Queue:DebugPrint("Player could not be added to the connecting list")
                return
            end

            Queue:RemoveFromQueue(ids)
            Queue:DebugPrint(name .. "[" .. ids[1] .. "] is loading into the server")

            deferrals.done()
            return
        end

        deferrals.update(msg)
    end

    updateDeferral(Config.Language.connecting)

    -- calling deferrals.done() too quickly was giving me problems
    Citizen.Wait(500)

    if not ids then
        -- prevent joining
        deferrals.done(Config.Language.err)
        Queue:DebugPrint("Dropped " .. name .. ", couldn't retrieve any of their id's")
        return
    end

    -- this will remove them from queue if they close the connecting screen
    if Queue:IsInQueue(ids) then
        Queue:RemoveFromQueue(ids)
        Queue:DebugPrint(string_format("%s[%s] was removed from queue, they cancelled connecting and attempted to rejoin", name, ids))
    end

    local reason = "You were kicked from joining the queue"
    local function setReason(msg)
        reason = tostring(msg)
    end

    TriggerEvent("queue:playerJoinQueue", src, setReason)
    if WasEventCanceled() then deferrals.done(reason) return end

    Queue:AddToQueue(ids, connectTime, name, src)

    if Queue:GetSize() <= 0 and Queue.PlayerCount + Queue:ConnectingSize() < maxPlayers and Queue:ConnectingSize() < 5 then
        -- let them in the server
       updateDeferral(nil, true)
       return
    end

    local pos, data = Queue:IsInQueue(ids, true)

    deferrals.update(string_format(Config.Language.pos, pos, Queue:GetSize()))

    Citizen.CreateThread(function()
        local dotCount = 0

        while true do
            Citizen.Wait(1000)

            local dots = ""

            dotCount = dotCount + 1
            if dotCount > 3 then dotCount = 0 end

            -- hopefully people will notice this and realize they don't have to keep reconnecting...
            for i = 1 , dotCount do dots = dots .. "." end

            local pos, data = Queue:IsInQueue(ids, true)

            -- will return false if not in queue; timed out?
            if not pos then return end

            -- prevent duplicating threads if player leaves and rejoins quickly
            if data.source ~= src then return end

            if pos <= 1 and Queue.PlayerCount + Queue:ConnectingSize() < maxPlayers and Queue:ConnectingSize() < 5 then
                updateDeferral(Config.Language.joining)

                Citizen.Wait(2000)

                -- let them in the server
                updateDeferral(nil, true)
                return
            end

            -- send status update
            local msg = string_format(Config.Language.pos .. "%s", pos, Queue:GetSize(), dots)
            updateDeferral(msg)
        end
    end)
end

AddEventHandler("playerConnecting", playerConnect)

local function playerActivated()
    local src = source
    local ids = Queue:GetIds(src)

    if not Queue.PlayerList[src] then
        Queue.PlayerCount = Queue.PlayerCount + 1
        Queue.PlayerList[src] = true
        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)
    end
end

RegisterServerEvent("Queue:playerActivated")
AddEventHandler("Queue:playerActivated", playerActivated)

local function playerDropped()
    local src = source
    local ids = Queue:GetIds(src)

    if Queue.PlayerList[src] then
        Queue.PlayerCount = Queue.PlayerCount - 1
        Queue.PlayerList[src] = nil
        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)
    end
end

AddEventHandler("playerDropped", playerDropped)

local function checkTimeOuts()
    Citizen.CreateThread(function()
        local i = 1

        while i <= Queue:GetSize() do
            local data = Queue.QueueList[i]

            -- check just incase there is invalid data
            if not data.ids or not data.name or not data.firstconnect or data.priority == nil or not data.source then
                table_remove(Queue.QueueList, i)
                Queue:DebugPrint(tostring(data.name) .. "[" .. tostring(data.ids[1]) .. "] was removed from the queue because it had invalid data")

            elseif (GetPlayerLastMsg(data.source) == 0 or GetPlayerLastMsg(data.source) >= 25000) and data.source ~= "debug" and os_time() - data.firstconnect > 5 then

                -- remove by source incase they rejoined and were duped in the queue somehow
                Queue:RemoveFromQueue(data.source, true)
                Queue:RemoveFromConnecting(data.source, true)
                Queue:DebugPrint(data.name .. "[" .. data.ids[1] .. "] was removed from the queue because they timed out")
            else
                i = i + 1
            end
        end

        local i = 1

        while i <= Queue:ConnectingSize() do
            local data = Queue.Connecting[i]

            if (GetPlayerLastMsg(data.source) == 0 or GetPlayerLastMsg(data.source) >= 25000) and data.source ~= "debug" and os_time() - data.firstconnect > 5 then
                Queue:RemoveFromQueue(data.ids)
                Queue:RemoveFromConnecting(data.ids)
                Queue:DebugPrint(data.name .. "[" .. data.ids[1] .. "] was removed from the connecting queue because they timed out")
            else
                i = i + 1
            end
        end

        local qCount = Queue:GetSize()

        -- show queue count in server name
        if displayQueue and initHostName then SetConvar("sv_hostname", (qCount > 0 and "[" .. tostring(qCount) .. "] " or "") .. initHostName) end

        SetTimeout(1000, checkTimeOuts)
    end)
end

checkTimeOuts()


-- debugging / testing commands
local testAdds = 0

AddEventHandler("rconCommand", function(command, args)
    -- adds a fake player to the queue for debugging purposes, this will freeze the queue
    if command == "addq" then
        print("==ADDED FAKE QUEUE==")
        Queue:AddToQueue({"steam:110000103fd1bb1"..testAdds}, os_time(), "Fake Player", "debug")
        testAdds = testAdds + 1
        CancelEvent()

    -- removes targeted id from the queue
    elseif command == "removeq" then
        if not args[1] then return end
        print("REMOVED " .. Queue.QueueList[tonumber(args[1])].name .. " FROM THE QUEUE")
        table_remove(Queue.QueueList, args[1])
        CancelEvent()
    
    -- print the current queue list
    elseif command == "printq" then
        print("==CURRENT QUEUE LIST==")
        for k,v in ipairs(Queue.QueueList) do
            print(k .. ": [src: " .. v.source .. "] " .. v.name .. "[" .. v.ids[1] .. "] | Priority: " .. (tostring(v.priority and true or false)) .. " | Last Msg: " .. GetPlayerLastMsg(v.source))
        end
        CancelEvent()

    -- adds a fake player to the connecting list
    elseif command == "addc" then
        print("==ADDED FAKE CONNECTING QUEUE==")
        Queue:AddToConnecting({"debug"})
        CancelEvent()

    -- removes a player from the connecting list
    elseif command == "removec" then
        print("==REMOVED FAKE CONNECTING QUEUE==")
        if not args[1] then return end
        table_remove(Queue.Connecting, args[1])
        CancelEvent()

    -- prints a list of players that are connecting
    elseif command == "printc" then
        print("==CURRENT CONNECTING LIST==")
        for k,v in ipairs(Queue.Connecting) do
            print(k .. ": [src: " .. v.source .. "] " .. v.name .. "[" .. v.ids[1] .. "] | Priority: " .. (tostring(v.priority and true or false)) .. " | Last Msg: " .. GetPlayerLastMsg(v.source))
        end
        CancelEvent()

    -- prints a list of activated players
    elseif command == "printl" then
        for k,v in pairs(Queue.PlayerList) do
            print(k .. ": " .. tostring(v))
        end
        CancelEvent()

    -- prints a list of priority id's
    elseif command == "printp" then
        print("==CURRENT PRIORITY LIST==")
        for k,v in pairs(Queue.Priority) do
            print(k .. ": " .. tostring(v))
        end
        CancelEvent()
    
    -- prints the current player count
    elseif command == "printcount" then
        print("Player Count: " .. Queue.PlayerCount)
        for k,v in pairs(GetPlayers()) do
            print(tostring(k) .. ": " .. tostring(v))
        end
        CancelEvent()
    end
end)

-- prevent duplicating queue count in server name
AddEventHandler("onResourceStop", function(resource)
    if displayQueue and resource == GetCurrentResourceName() then SetConvar("sv_hostname", initHostName) end
end)

--[[

AddEventHandler("queue:playerJoinQueue", function(src, setKickReason)
    setKickReason("No, you can't join")
    CancelEvent()
end)

exports.connectqueue:AddPriority("steam:110000#####", 50)
exports.connectqueue:AddPriority("ip:127.0.0.1", 50)
exports.connectqueue:AddPriority("STEAM_0:1:########", 50)

local prioritize = {
    ["STEAM_0:1:########"] = 10,
    ["ip:127.0.0.1"] = 20,
    ["steam:110000#####"] = 100
}
exports.connectqueue:AddPriority(prioritize)

exports.connectqueue:RemovePriority("STEAM_0:1:########")

set sv_debugqueue true
set sv_displayqueue true

 ]]