if not IsDuplicityVersion() then
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            if NetworkIsSessionStarted() then
                TriggerServerEvent("Queue:playerActivated")
                return
            end
        end
    end)
    return
end

local Queue = {}
Queue.QueueList = {}
Queue.PlayerList = {}
Queue.PlayerCount = 0
Queue.Priority = {}
Queue.Connecting = {}
Queue.JoinCbs = {}
Queue.TempPriority = {}

-- EDIT THESE IN SERVER.CFG + OTHER OPTIONS IN CONFIG.LUA
Queue.MaxPlayers = GetConvarInt("sv_maxclients", 30)
Queue.Debug = GetConvar("sv_debugqueue", "true") == "true" and true or false
Queue.DisplayQueue = GetConvar("sv_displayqueue", "true") == "true" and true or false
Queue.InitHostName = GetConvar("sv_hostname")

local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local print = print
local string_len = string.len
local string_sub = string.sub
local string_format = string.format
local string_lower = string.lower
local math_abs = math.abs
local math_floor = math.floor
local math_random = math.random
local os_time = os.time
local table_insert = table.insert
local table_remove = table.remove

Queue.InitHostName = Queue.InitHostName ~= "default FXServer" and Queue.InitHostName or false

for id, power in pairs(Config.Priority) do
    Queue.Priority[string_lower(id)] = power
end

function Queue:HexIdToSteamId(hexId)
    local cid = math_floor(tonumber(string_sub(hexId, 7), 16))
	local steam64 = math_floor(tonumber(string_sub( cid, 2)))
	local a = steam64 % 2 == 0 and 0 or 1
	local b = math_floor(math_abs(6561197960265728 - steam64 - a) / 2)
	local sid = "steam_0:"..a..":"..(a == 1 and b -1 or b)
    return sid
end

function Queue:IsSteamRunning(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if string_sub(id, 1, 5) == "steam" then
            return true
        end
    end
    
    return false
end

function Queue:DebugPrint(msg)
    if Queue.Debug then
        msg = "^3QUEUE: ^0" .. tostring(msg) .. "^7"
        print(msg)
    end
end

function Queue:IsInQueue(ids, rtnTbl, bySource, connecting)
    for genericKey1, genericValue1 in ipairs(connecting and self.Connecting or self.QueueList) do
        local inQueue = false

        if not bySource then
            for genericKey2, genericValue2 in ipairs(genericValue1.ids) do
                if inQueue then break end

                for genericKey3, genericValue3 in ipairs(ids) do
                    if genericValue3 == genericValue2 then inQueue = true break end
                end
            end
        else
            inQueue = ids == genericValue1.source
        end

        if inQueue then
            if rtnTbl then
                return genericKey1, connecting and self.Connecting[genericKey1] or self.QueueList[genericKey1]
            end

            return true
        end
    end

    return false
end

function Queue:IsPriority(ids)
    local prio = false
    local tempPower, tempEnd = self:HasTempPriority(ids)

    for _, id in ipairs(ids) do
        id = string_lower(id)

        if self.Priority[id] then prio = self.Priority[id] break end

        if string_sub(id, 1, 5) == "steam" then
            local steamid = self:HexIdToSteamId(id)
            if self.Priority[steamid] then prio = self.Priority[steamid] break end
        end
    end

    if tempPower or prio then
        if tempPower and prio then
            return tempPower > prio and tempPower or prio
        else
            return tempPower or prio
        end
    end

    return false
end

function Queue:HasTempPriority(ids)
    for _, id in pairs(ids) do
        id = string_lower(id)

        if self.TempPriority[id] then return self.TempPriority[id].power, self.TempPriority[id].endTime, id end

        if string_sub(id, 1, 5) == "steam" then
            local steamid = self:HexIdToSteamId(id)
            if self.TempPriority[steamid] then return self.TempPriority[steamid].power, self.TempPriority[steamid].endTime, id end
        end
    end

    return false
end

function Queue:AddToQueue(ids, connectTime, name, src, deferrals)
    if self:IsInQueue(ids) then return end

    local tmp = {
        source = src,
        ids = ids,
        name = name,
        priority = self:IsPriority(ids) or (src == "debug" and math_random(0, 15)),
        timeout = 0,
        deferrals = deferrals,
        firstconnect = connectTime,
        queuetime = function() return (os_time() - connectTime) end
    }

    local _pos = false
    local queueCount = self:GetSize() + 1

    for pos, data in ipairs(self.QueueList) do
        if tmp.priority then
            if not data.priority then
                _pos = pos
            else
                if tmp.priority > data.priority then
                    _pos = pos
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

function Queue:TempSize()
    local count = 0

    for _pos, data in pairs(Queue.QueueList) do
        if Queue:HasTempPriority(data.ids) then count = count +1 end
    end

    return count > 0 and count or false
end

function Queue:IsInConnecting(ids, bySource, refresh)
    local inConnecting, tbl = self:IsInQueue(ids, refresh and true or false, bySource and true or false, true)

    if not inConnecting then return false end

    if refresh and inConnecting and tbl then
        self.Connecting[inConnecting].timeout = 0
    end

    return true
end

function Queue:RemoveFromConnecting(ids, bySource)
    for genericKey1, genericValue1 in ipairs(self.Connecting) do
        local inConnecting = false

        if not bySource then
            for genericKey2, genericValue2 in ipairs(genericValue1.ids) do
                if inConnecting then break end

                for genericKey3, genericValue3 in ipairs(ids) do
                    if genericValue3 == genericValue2 then inConnecting = true break end
                end
            end
        else
            inConnecting = ids == genericValue1.source
        end

        if inConnecting then
            table_remove(self.Connecting, genericKey1)
            return true
        end
    end

    return false
end

function Queue:AddToConnecting(ids, ignorePos, autoRemove, done)
    local function remove()
        if not autoRemove then return end

        done(Config.Language.connectingerr)
        self:RemoveFromConnecting(ids)
        self:RemoveFromQueue(ids)
        self:DebugPrint("Player could not be added to the connecting list")
    end

    if self:ConnectingSize() + self.PlayerCount + 1 > Queue.MaxPlayers then remove() return false end
    
    if ids[1] == "debug" then
        table_insert(self.Connecting, {source = ids[1], ids = ids, name = ids[1], firstconnect = ids[1], priority = ids[1], timeout = 0})
        return true
    end

    if self:IsInConnecting(ids) then self:RemoveFromConnecting(ids) end

    local pos, data = self:IsInQueue(ids, true)
    if not ignorePos and (not pos or pos > 1) then remove() return false end

    table_insert(self.Connecting, data)
    self:RemoveFromQueue(ids)

    return true
end

function Queue:GetIds(src)
    local ids = GetPlayerIdentifiers(src)
    local ip = GetPlayerEndpoint(src)
    
    ids = (ids and ids[1]) and ids or (ip and {"ip:" .. ip} or false)
    ids = ids ~= nil and ids or false

    if ids and #ids > 1 then
        for k, id in ipairs(ids) do
            if string_sub(id, 1, 3) == "ip:" then table_remove(ids, k) end
        end
    end

    return ids
end

function Queue:AddPriority(id, power, temp)
    if not id then return false end

    if type(id) == "table" then
        for _id, power in pairs(id) do
            if _id and type(_id) == "string" and power and type(power) == "number" then
                Queue.Priority[_id] = power
            else
                Queue:DebugPrint("Error adding a priority id, invalid data passed")
                return false
            end
        end

        return true
    end

    power = (power and type(power) == "number") and power or 10

    if temp then
        local tempPower, tempEnd, tempId = Queue:HasTempPriority({id})
        id = tempId or id

        Queue.TempPriority[string_lower(id)] = {power = power, endTime = os_time() + temp} 
    else
        Queue.Priority[string_lower(id)] = power
    end
    
    return true
end

function Queue:RemovePriority(id)
    if not id then return false end
    id = string_lower(id)
    Queue.Priority[id] = nil
    return true
end

function Queue:UpdatePosData(src, ids, deferrals)
    local pos, data = self:IsInQueue(ids, true)
    self.QueueList[pos].source = src
    self.QueueList[pos].ids = ids
    self.QueueList[pos].timeout = 0
    self.QueueList[pos].firstconnect = os_time()
    self.QueueList[pos].name = GetPlayerName(src)
    self.QueueList[pos].deferrals = deferrals
end

function Queue:NotFull(firstJoin)
    local canJoin = self.PlayerCount + self:ConnectingSize() < Queue.MaxPlayers
    if firstJoin and canJoin then canJoin = self:GetSize() <= 1 end
    return canJoin
end

function Queue:SetPos(ids, newPos)
    local pos, data = self:IsInQueue(ids, true)

    table_remove(self.QueueList, pos)
    table_insert(self.QueueList, newPos, data)

    Queue:DebugPrint("Set " .. data.name .. "[" .. data.ids[1] .. "] pos to " .. newPos)
end

function Queue:CanJoin(src, cb)
    local allow = true

    for _, data in ipairs(self.JoinCbs) do
        local await = true

        data.func(src, function(reason)
            if reason and type(reason) == "string" then allow = false cb(reason) end
            await = false
        end)

        while await do Citizen.Wait(0) end

        if not allow then return end
    end

    if allow then cb(false) end
end

function Queue:OnJoin(cb, resource)
    if not cb then return end

    local tmp = {resource = resource, func = cb}
    table_insert(Queue.JoinCbs, tmp)
end

exports("Exports", function()
    return Queue
end)

local function playerConnect(name, setKickReason, deferrals)
    local src = source
    local ids = Queue:GetIds(src)
    local name = GetPlayerName(src)
    local connectTime = os_time()
    local connecting = true

    deferrals.defer()

    Citizen.CreateThread(function()
        while connecting do
            Citizen.Wait(100)
            if not connecting then return end
            deferrals.update(Config.Language.connecting)
        end
    end)

    Citizen.Wait(500)

    local function done(msg, _deferrals)
        connecting = false

        local deferrals = _deferrals or deferrals

        if msg then deferrals.update(tostring(msg) or "") end

        Citizen.Wait(500)

        if not msg then
            deferrals.done()
            if Config.EnableGrace then Queue:AddPriority(ids[1], Config.GracePower, Config.GraceTime) end
        else
            deferrals.done(tostring(msg) or "") CancelEvent()
        end

        return
    end

    local function update(msg, _deferrals)
        local deferrals = _deferrals or deferrals
        connecting = false
        deferrals.update(tostring(msg) or "")
    end

    if not ids then
        -- prevent joining
        done(Config.Language.iderr)
        CancelEvent()
        Queue:DebugPrint("Dropped " .. name .. ", couldn't retrieve any of their id's")
        return
    end

    if Config.RequireSteam and not Queue:IsSteamRunning(src) then
        -- prevent joining
        done(Config.Language.steam)
        CancelEvent()
        return
    end

    local allow

    Queue:CanJoin(src, function(reason)
        if reason == nil or allow ~= nil then return end
        if reason == false or #Queue.JoinCbs <= 0 then allow = true return end

        if reason then
            -- prevent joining
            allow = false
            done(reason and tostring(reason) or "You were blocked from joining")
            Queue:RemoveFromQueue(ids)
            Queue:RemoveFromConnecting(ids)
            Queue:DebugPrint(string_format("%s[%s] was blocked from joining; Reason: %s", name, ids[1], reason))
            CancelEvent()
            return
        end

        allow = true
    end) 

    while allow == nil do Citizen.Wait(0) end
    if not allow then return end

    if Config.PriorityOnly and not Queue:IsPriority(ids) then done(Config.Language.wlonly) return end

    local rejoined = false

    if Queue:IsInConnecting(ids, false, true) then
        Queue:RemoveFromConnecting(ids)

        if Queue:NotFull() then
            -- let them in the server

            if not Queue:IsInQueue(ids) then
                Queue:AddToQueue(ids, connectTime, name, src, deferrals)
            end

            local added = Queue:AddToConnecting(ids, true, true, done)
            if not added then CancelEvent() return end
            done()

            return
        else
            rejoined = true
        end
    end

    if Queue:IsInQueue(ids) then
        rejoined = true
        Queue:UpdatePosData(src, ids, deferrals)
        Queue:DebugPrint(string_format("%s[%s] has rejoined queue after cancelling", name, ids[1]))
    else
        Queue:AddToQueue(ids, connectTime, name, src, deferrals)

        if rejoined then
            Queue:SetPos(ids, 1)
            rejoined = false
        end
    end

    local pos, data = Queue:IsInQueue(ids, true)
    
    if not pos or not data then
        done(Config.Language.err .. " [3]")

        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)

        CancelEvent()
        return
    end

    if Queue:NotFull(true) then
        -- let them in the server
        local added = Queue:AddToConnecting(ids, true, true, done)
        if not added then CancelEvent() return end

        done()
        Queue:DebugPrint(name .. "[" .. ids[1] .. "] is loading into the server")

        return
    end
    
    update(string_format(Config.Language.pos .. ((Queue:TempSize() and Config.ShowTemp) and " (" .. Queue:TempSize() .. " temp)" or "00:00:00"), pos, Queue:GetSize(), ""))

    if rejoined then return end

    while true do
        Citizen.Wait(500)

        local pos, data = Queue:IsInQueue(ids, true)

        local function remove(msg)
            if data then
                if msg then
                    update(msg, data.deferrals)
                end

                Queue:RemoveFromQueue(data.source, true)
                Queue:RemoveFromConnecting(data.source, true)
            else
                Queue:RemoveFromQueue(ids)
                Queue:RemoveFromConnecting(ids)
            end
        end

        if not data or not data.deferrals or not data.source or not pos then
            remove("Removed from queue, queue data invalid :(")
            Queue:DebugPrint(tostring(name .. "[" .. ids[1] .. "] was removed from the queue because they had invalid data"))
            return
        end

        local lastMsg = GetPlayerLastMsg(data.source)
        if lastMsg >= 30000 then data.timeout = data.timeout + 0.5 else data.timeout = 0 end

        if data.timeout >= Config.QueueTimeOut and os_time() - connectTime > 5 then
            remove("Removed due to timeout")
            Queue:DebugPrint(name .. "[" .. ids[1] .. "] was removed from the queue because they timed out")
            return
        end

        if pos <= 1 and Queue:NotFull() then
            -- let them in the server
            local added = Queue:AddToConnecting(ids)

            update(Config.Language.joining, data.deferrals)
            Citizen.Wait(500)

            if not added then
                done(Config.Language.connectingerr)
                CancelEvent()
                return
            end

            done(nil, data.deferrals)

            if Config.EnableGrace then Queue:AddPriority(ids[1], Config.GracePower, Config.GraceTime) end

            Queue:RemoveFromQueue(ids)
            Queue:DebugPrint(name .. "[" .. ids[1] .. "] is loading into the server")
            return
        end

        local seconds = data.queuetime()
        local qTime = string_format("%02d", math_floor((seconds % 86400) / 3600)) .. ":" .. string_format("%02d", math_floor((seconds % 3600) / 60)) .. ":" .. string_format("%02d", math_floor(seconds % 60))

        local msg = string_format(Config.Language.pos .. ((Queue:TempSize() and Config.ShowTemp) and " (" .. Queue:TempSize() .. " temp)" or ""), pos, Queue:GetSize(), qTime)
        update(msg, data.deferrals)
    end
end
AddEventHandler("playerConnecting", playerConnect)

Citizen.CreateThread(function()
    local function remove(data, pos, msg)
        if data and data.source then
            Queue:RemoveFromQueue(data.source, true)
            Queue:RemoveFromConnecting(data.source, true)
        elseif pos then
            table_remove(Queue.QueueList, pos)
        end
    end

    while true do
        Citizen.Wait(1000)
    
        local i = 1
    
        while i <= Queue:ConnectingSize() do
            local data = Queue.Connecting[i]
    
            local lastMsg = GetPlayerLastMsg(data.source)
    
            data.timeout = data.timeout + 1
    
            if ((data.timeout >= 300 and lastMsg >= 60000) or data.timeout >= Config.ConnectTimeOut) and data.source ~= "debug" and os_time() - data.firstconnect > 5 then
                remove(data)
                Queue:DebugPrint(data.name .. "[" .. data.ids[1] .. "] was removed from the connecting queue because they timed out")
            else
                i = i + 1
            end
        end

        for id, data in pairs(Queue.TempPriority) do
            if os_time() >= data.endTime then
                Queue.TempPriority[id] = nil
            end
        end
    
        Queue.MaxPlayers = GetConvarInt("sv_maxclients", 30)
        Queue.Debug = GetConvar("sv_debugqueue", "true") == "true" and true or false
        Queue.DisplayQueue = GetConvar("sv_displayqueue", "true") == "true" and true or false

        local qCount = Queue:GetSize()

        if Queue.DisplayQueue then
            if Queue.InitHostName then
                SetConvar("sv_hostname", (qCount > 0 and "[" .. tostring(qCount) .. "] " or "") .. Queue.InitHostName)
            else
                Queue.InitHostName = GetConvar("sv_hostname")
                Queue.InitHostName = Queue.InitHostName ~= "default FXServer" and Queue.InitHostName or false
            end
        end
    end
end)

RegisterServerEvent("Queue:playerActivated")
AddEventHandler("Queue:playerActivated", function()
    local src = source
    local ids = Queue:GetIds(src)

    if not Queue.PlayerList[src] then
        Queue.PlayerCount = Queue.PlayerCount + 1
        Queue.PlayerList[src] = true
        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    local ids = Queue:GetIds(src)

    if Queue.PlayerList[src] then
        Queue.PlayerCount = Queue.PlayerCount - 1
        Queue.PlayerList[src] = nil
        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)
        if Config.EnableGrace then Queue:AddPriority(ids[1], Config.GracePower, Config.GraceTime) end
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if Queue.DisplayQueue and Queue.InitHostName and resource == GetCurrentResourceName() then SetConvar("sv_hostname", Queue.InitHostName) end
    
    for k, data in ipairs(Queue.JoinCbs) do
        if data.resource == resource then
            table_remove(Queue.JoinCbs, k)
        end
    end
end)

if Config.DisableHardCap then
    Queue:DebugPrint("^1 [connectqueue] Disabling hardcap ^7")

    AddEventHandler("onResourceStarting", function(resource)
        if resource == "hardcap" then CancelEvent() return end
    end)
    
    StopResource("hardcap")
end

local testAdds = 0
local commands = {}

commands.addq = function()
    Queue:DebugPrint("ADDED DEBUG QUEUE")
    Queue:AddToQueue({"steam:110000103fd1bb1"..testAdds}, os_time(), "TestAdd: " .. testAdds, "debug")
    testAdds = testAdds + 1
end

commands.removeq = function(args)
    Queue:DebugPrint("REMOVED " .. Queue.QueueList[tonumber(args[1])].name .. " FROM THE QUEUE")
    table_remove(Queue.QueueList, args[1])
    testAdds = testAdds + 1
end

commands.printq = function()
    Queue:DebugPrint("CURRENT QUEUE LIST")
    for pos, data in ipairs(Queue.QueueList) do
        Queue:DebugPrint(pos .. ": [src: " .. data.source .. "] " .. data.name .. "[" .. data.ids[1] .. "] | Priority: " .. (tostring(data.priority and data.priority or false)) .. " | Last Msg: " .. (data.source ~= "debug" and GetPlayerLastMsg(data.source) or "debug") .. " | Timeout: " .. data.timeout .. " | Queue Time: " .. data.queuetime() .. " Seconds")
    end
end

commands.addc = function()
    Queue:DebugPrint("ADDED DEBUG CONNECTING QUEUE")
    Queue:AddToConnecting({"debug"})
end

commands.removec = function(args)
    Queue:DebugPrint("REMOVED DEBUG CONNECTING QUEUE")
    if not args[1] then return end
    table_remove(Queue.Connecting, args[1])
end

commands.printc = function()
    Queue:DebugPrint("CURRENT CONNECTING LIST")
    for pos, data in ipairs(Queue.Connecting) do
        Queue:DebugPrint(pos .. ": [src: " .. data.source .. "] " .. data.name .. "[" .. data.ids[1] .. "] | Priority: " .. (tostring(data.priority and data.priority or false)) .. " | Last Msg: " .. (data.source ~= "debug" and GetPlayerLastMsg(data.source) or "debug") .. " | Timeout: " .. data.timeout)
    end
end

commands.printl = function()
    for k, joined in pairs(Queue.PlayerList) do
        Queue:DebugPrint(k .. ": " .. tostring(joined))
    end
end

commands.printp = function()
    Queue:DebugPrint("CURRENT PRIORITY LIST")
    for id, power in pairs(Queue.Priority) do
        Queue:DebugPrint(id .. ": " .. tostring(power))
    end
end

commands.printcount = function()
    Queue:DebugPrint("Player Count: " .. Queue.PlayerCount)
end

commands.printtp = function()
    Queue:DebugPrint("CURRENT TEMP PRIORITY LIST")
    for k, data in pairs(Queue.TempPriority) do
        Queue:DebugPrint(k .. ": Power: " .. tostring(data.power) .. " | EndTime: " .. tostring(data.endTime) .. " | CurTime: " .. tostring(os_time()))
    end
end

commands.removetp = function(args)
    if not args[1] then return end
    Queue.TempPriority[args[1]] = nil
    Queue:DebugPrint("REMOVED " .. args[1] .. " FROM THE TEMP PRIORITY LIST")
end

commands.setpos = function(args)
    if not args[1] or not args[2] then return end
    args[1], args[2] = tonumber(args[1]), tonumber(args[2])
    Queue:DebugPrint("SET " .. Queue.QueueList[args[1]].name .. "'s' QUEUE POSITION TO: " .. args[2])
    local ids = Queue.QueueList[args[1]].ids
    Queue:SetPos(ids, args[2])
end

commands.setdata = function(args)
    if not args[1] or not args[2] or not args[3] then return end
    local num = tonumber(args[3])

    if args[2] == "queuetime" then
        local time = Queue.QueueList[tonumber(args[1])].queuetime()
        local dif = time - num
        Queue.QueueList[tonumber(args[1])].firstconnect = Queue.QueueList[tonumber(args[1])].firstconnect + dif
        Queue.QueueList[tonumber(args[1])].queuetime = function() return (os_time() - Queue.QueueList[tonumber(args[1])].firstconnect) end
    else
        Queue.QueueList[tonumber(args[1])][args[2]] = num and num or args[3]
    end

    Queue:DebugPrint("SET " .. Queue.QueueList[tonumber(args[1])].name .. "'s " .. args[2] .. " DATA TO " .. args[3])
end

commands.printcommands = function()
    for cmd, func in pairs(commands) do
        Queue:DebugPrint(tostring(cmd))
    end
end

AddEventHandler("rconCommand", function(command, args)
    if command == "queue" and commands[args[1]] then
        command = args[1]
        table_remove(args, 1)
        commands[command](args)
        CancelEvent()
    end
end)