local Config = {}
----------------------------------------------------------------------------------------------------------------------
-- Priority list takes SteamID 32's or HexID's, the integer is their power over other users
Config.Priority = {
    ["STEAM_0:1:########"] = 8,
    ["STEAM_0:1:########"] = 150,
    ["STEAM_0:1:########"] = 25,
    ["STEAM_0:1:########"] = 100,
    ["steam:11000010######"] = 75,
    ["steam:11000010######"] = 80
}

-- will show debug information in the console
Config.Debug = true

-- display queue count in server name Note: sv_hostname must be set before starting this resource in server.cfg
Config.DisplayQueue = true

-- easy localization
Config.Language = {
    joining = "Joining...",
    connecting = "Connecting...",
    steamid = "Error: We couldn't retrieve your SteamID, try restarting steam",
    pos = "You are %d/%d in queue"
}
-----------------------------------------------------------------------------------------------------------------------

local Queue = {}
Queue.QueueList = {}
Queue.PlayerList = {}
Queue.PlayerCount = 0
Queue.Priority = Config.Priority
Queue.Connecting = {}

local initHostName = GetConvar("sv_hostname")
Config.MaxPlayers = GetConvarInt("sv_maxclients")

local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local print = print
local string_sub = string.sub
local string_format = string.format
local math_abs = math.abs
local math_floor = math.floor
local os_time = os.time
local table_insert = table.insert
local table_remove = table.remove

-- converts hex steamid to SteamID 32
function Queue:HexIdToSteamId(hexId)
    local cid = math_floor(tonumber(string_sub(hexId, 7), 16))
	local steam64 = math_floor(tonumber(string_sub( cid, 2)))
	local a = steam64 % 2 == 0 and 0 or 1
	local b = math_floor(math_abs(6561197960265728 - steam64 - a) / 2)
	local sid = "STEAM_0:"..a..":"..(a == 1 and b -1 or b)
    return sid
end

function Queue:DebugPrint(msg)
    if Config.Debug then
        msg = "QUEUE: " .. tostring(msg)
        print(msg)
    end
end

function Queue:IsInQueue(hexId, rtnTbl, bySource)
    for k,v in ipairs(self.QueueList) do
        local _type = bySource and v.source or v.hexid

        if _type == hexId then
            if rtnTbl then
                return k, self.QueueList[k]
            else
                return true
            end
        end
    end

    return false
end

function Queue:IsPriority(hexId)
    if Queue.Priority[hexId] then return Queue.Priority[hexId]  ~= nil and Queue.Priority[hexId] or false end

    local steamid = Queue:HexIdToSteamId(hexId)
    return Queue.Priority[steamid] ~= nil and Queue.Priority[steamid] or false
end

function Queue:AddToQueue(hexId, connectTime, name, src)
    if self:IsInQueue(hexId) then return end

    local tmp = {
        source = src,
        hexid = hexId,
        name = name,
        firstconnect = connectTime,
        priority = self:IsPriority(hexId) or (src == "debug" and math.random(0, 15))
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
                self:DebugPrint(string_format("%s[%s] was prioritized and placed %d/%d in queue", tmp.name, hexId, _pos, queueCount))
                break
            end
        end
    end

    if not _pos then
        _pos = self:GetSize() + 1
        self:DebugPrint(string_format("%s[%s] was placed %d/%d in queue", tmp.name, hexId, _pos, queueCount))
    end

    table_insert(self.QueueList, _pos, tmp)
end

function Queue:RemoveFromQueue(hexId, bySource)
    if self:IsInQueue(hexId, false, bySource) then
        local pos, data = self:IsInQueue(hexId, true, bySource)
        table_remove(self.QueueList, pos)
    end
end

function Queue:GetSize()
    return #self.QueueList
end

function Queue:GetConnectingSize()
    local count = 0
    
    for k,v in pairs(self.Connecting) do
        count = count + 1
    end

    return count
end

function Queue:IsInConnecting(hexId, bySource)
    for k,v in ipairs(self.Connecting) do
        local _type = bySource and v.source or v.hexid

        if _type == hexId then return true end
    end

    return false
end

function Queue:AddToConnecting(hexId)
    if self:GetConnectingSize() >= 5 then return false end

    if hexId == "debug" then
        table_insert(self.Connecting, {source = hexId, hexid = hexId, name = hexId, firstconnect = hexId, priority = hexId})
        return true
    end

    if self:IsInConnecting(hexId) then self:RemoveFromConnecting(hexId) end

    local pos, data = self:IsInQueue(hexId, true)

    if not pos or pos > 1 then return false end

    table_insert(self.Connecting, data)
    return true
end

function Queue:RemoveFromConnecting(hexId, bySource)
    for k,v in ipairs(self.Connecting) do
        local _type = bySource and v.source or v.hexid

        if _type == hexId then
            table_remove(self.Connecting, k)
            return true
        end
    end

    return false
end

function Queue:GetId(src)
    local hexId = GetPlayerIdentifiers(src)
    hexId = (hexId and hexId[1]) and hexId[1] or false
    return hexId
end

-- id's can be either be hex id or 32 bit steamid, this will allow custom scripts to add priorities using other means... like grabbing them from a db.
-- can also take a table of steamid's and their power allowing you to call this event only once instead of in a loop for each individual.
function Queue:AddPriority(id, power)
    if not id then return false end

    if type(id) == "table" then
        for k, v in pairs(id) do
            if k and type(k) == "string" and v and type(v) == "number" then
                Queue.Priority[k] = v
            else
                Queue:DebugPrint("Error adding a priority id, invalid data passed")
            end
        end

        return true
    end

    power = (power and type(power) == "number") and power or 50
    Queue.Priority[id] = power

    return true
end

function Queue:RemovePriority(id)
    if not id then return false end
    Queue.Priority[id] = nil
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
    local src = source
    local hexId = Queue:GetId(src)
    local connectTime = os_time()

    deferrals.defer()

    local function updateDeferral(msg, letJoin)
        if letJoin then
            local added = Queue:AddToConnecting(hexId)
            if not added then
                Queue:RemoveFromQueue(hexId)
                Queue:RemoveFromConnecting(hexId)
                Queue:DebugPrint("Player could not be added to the connecting list")
                return
            end

            Queue:RemoveFromQueue(hexId)

            deferrals.done()
            return
        end

        deferrals.update(msg)
    end

    updateDeferral(Config.Language.connecting)

    -- calling deferrals.done() too quickly was giving me problems
    Citizen.Wait(500)

    if not hexId or hexId == "" then
        -- prevent joining
        deferrals.done(Config.Language.steamid)
        Queue:DebugPrint("Dropped " .. name .. ", couldn't retrieve their steamid")
        return
    end

    -- this means leaving the connecting screen will remove you from queue, so don't leave it...
    if Queue:IsInQueue(hexId) then
        Queue:RemoveFromQueue(hexId)
        Queue:DebugPrint(string_format("%s[%s] was removed from queue, they cancelled connecting and attempted to rejoin", name, hexId))
    end

    Queue:AddToQueue(hexId, connectTime, name, src)

    if Queue:GetSize() <= 0 and Queue.PlayerCount < Config.MaxPlayers and Queue:GetConnectingSize() < 5 then
        -- let them in the server
       updateDeferral(nil, true)
       return
    end

    local pos, data = Queue:IsInQueue(hexId, true)

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

            local pos, data = Queue:IsInQueue(hexId, true)

            -- will return false if not in queue; timed out?
            if not pos then return end

            -- prevent duplicating threads if player leaves and rejoins quickly
            if data.source ~= src then return end

            if pos <= 1 and Queue.PlayerCount < Config.MaxPlayers and Queue:GetConnectingSize() < 5 then
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
    local hexId = Queue:GetId(src)

    if not Queue.PlayerList[src] then
        Queue.PlayerCount = Queue.PlayerCount + 1
        Queue.PlayerList[src] = true
        Queue:RemoveFromQueue(hexId)
        Queue:RemoveFromConnecting(hexId)
    end
end

RegisterServerEvent("Queue:playerActivated")
AddEventHandler("Queue:playerActivated", playerActivated)

local function playerDropped()
    local src = source
    local hexId = Queue:GetId(src)

    if Queue.PlayerList[src] then
        Queue.PlayerCount = Queue.PlayerCount - 1
        Queue.PlayerList[src] = nil
        Queue:RemoveFromQueue(hexId)
        Queue:RemoveFromConnecting(hexId)
    end
end

AddEventHandler("playerDropped", playerDropped)

local function checkTimeOuts()
    Citizen.CreateThread(function()
        local i = 1

        while i <= Queue:GetSize() do
            local data = Queue.QueueList[i]

            -- check just incase there is invalid data
            if not data.hexid or not data.name or not data.firstconnect or data.priority == nil or not data.source then
                table_remove(Queue.QueueList, i)
                Queue:DebugPrint(tostring(data.name) .. "[" .. tostring(data.hexid) .. "] was removed from the queue because it had invalid data")

            elseif (GetPlayerLastMsg(data.source) == 0 or GetPlayerLastMsg(data.source) >= 30000) and data.source ~= "debug" and os_time() - data.firstconnect > 5 then

                -- remove by source incase they rejoined and were duped in the queue somehow
                Queue:RemoveFromQueue(data.source, true)
                Queue:RemoveFromConnecting(data.source, true)
                Queue:DebugPrint(data.name .. "[" .. data.hexid .. "] was removed from the queue because they timed out")
            else
                i = i + 1
            end
        end

        while i <= Queue:GetConnectingSize() do
            local data = Queue.Connecting[i]
            if (GetPlayerLastMsg(data.source) == 0 or GetPlayerLastMsg(data.source) >= 30000) and data.source ~= "debug" and os_time() - data.firstconnect > 5 then
                Queue:RemoveFromConnecting(data.source, true)
                Queue:RemoveFromQueue(data.source, true)
                Queue:DebugPrint(data.name .. "[" .. data.hexid .. "] was removed from the connecting queue because they timed out")
            else
                i = i + 1
            end
        end

        --[[ for k,v in pairs(Queue.List) do
            local lstMsg = GetPlayerLastMsg(k)

            if not lstMsg or lstMsg == 0 or lstMsg >= 120000 then
                Queue.List[k] = nil
                Queue.PlayerCount = Queue.PlayerCount - 1
            end
        end ]]

        local qCount = Queue:GetSize()

        -- show queue count in server name
        if Config.DisplayQueue then SetConvar("sv_hostname", (qCount > 0 and "[" .. tostring(qCount) .. "] " or "") .. initHostName) end

        SetTimeout(1000, checkTimeOuts)
    end)
end

checkTimeOuts()

local testAdds = 0

AddEventHandler("rconCommand", function(command, args)
    -- adds a fake player to the queue for debugging purposes, this will freeze the queue
    if command == "addq" then
        print("==ADDED FAKE QUEUE==")
        Queue:AddToQueue("steam:110000103fd1bb1"..testAdds, os_time(), "Fake Player", "debug")
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
            print(k .. ": [id: " .. v.source .. "] " .. v.name .. "[" .. v.hexid .. "] | Priority: " .. (tostring(v.priority and true or false)) .. " | Last Msg: " .. GetPlayerLastMsg(v.source))
        end
        CancelEvent()

    -- adds a fake player to the connecting list
    elseif command == "addc" then
        print("==ADDED FAKE CONNECTING QUEUE==")
        Queue:AddToConnecting("debug")
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
                print(k .. ": [id: " .. v.source .. "] " .. v.name .. "[" .. v.hexid .. "] | Priority: " .. (tostring(v.priority and true or false)) .. " | Last Msg: " .. GetPlayerLastMsg(v.source))
        end

    -- prints a list of activated players
    elseif command == "printl" then
        for k,v in pairs(Queue.PlayerList) do
            print(k .. ": " .. tostring(v))
        end
        CancelEvent()

    elseif command == "printp" then
        print("==CURRENT PRIORITY LIST==")
        for k,v in pairs(Config.Priority) do
            print(k .. ": " .. tostring(v))
        end
        CancelEvent()
    
    -- prints the current player count
    elseif command == "printcount" then
        print("Player Count: " .. Queue.PlayerCount)
    end
end)

-- prevent duplicating queue count in server name
AddEventHandler("onResourceStop", function(resource)
    if Config.DisplayQueue and resource == GetCurrentResourceName() then SetConvar("sv_hostname", initHostName) end
end)