# ConnectQueue
---
Easy to use queue system for FiveM with:
- Simple API
- Priority System
- Config
    - Ability for whitelist only
    - Require steam
    - Language options

**Please report any bugs on the release thread [Here](https://forum.fivem.net/t/alpha-connectqueue-a-server-queue-system-fxs/22228) or through [GitHub](https://github.com/Nick78111/ConnectQueue/issues).**

## How to install
---
- Drop the folder inside your resources folder.
- Add `start connectqueue` inside your server.cfg. - *Preferrably at the top*
- Set convars to your liking.
- Open `connectqueue/server/sv_queue_config.lua` and edit to your liking.
- Renaming the resource may cause problems.

## ConVars
---
	set sv_debugqueue true # prints debug messages to console
	set sv_displayqueue true # shows queue count in the server name '[count] server name'

## How to use / Examples
---
To use the API add `server_script "@connectqueue/connectqueue.lua"` at the top of the `__resource.lua` file in question.
I would also suggest adding `dependency "connectqueue"` to it aswell.
You may now use any of the functions below, anywhere in that resource.

### OnReady
This is called when the queue functions are ready to be used.
```Lua
    Queue.OnReady(function() 
        print("HI")
    end)
```
All of the functions below must be called **AFTER** the queue is ready.

### OnJoin
This is called when a player tries to join the server.
Calling `allow` with no arguments will let them through.
Calling `allow` with a string will prevent them from joining with the given message.
`allow` must be called or the player will hang on connecting...
```Lua
Queue.OnJoin(function(source, allow)
    allow("No, you can't join")
end)
```

## AddPriority
Call this to add an identifier to the priority list.
The integer is how much power they have over other users with priority.
This function can take a table of ids or individually.
```Lua
-- individual
Queue.AddPriority("STEAM_0:1:33459672", 100)
Queue.AddPriority("steam:110000103fd1bb1", 10)
Queue.AddPriority("ip:127.0.0.1", 25)

-- table
local prioritize = {
    ["STEAM_0:1:33459672"] = 100,
    ["steam:110000103fd1bb1"] = 10,
    ["ip:127.0.0.1"] = 25,
}
Queue.AddPriority(prioritize)
```

## RemovePriority
Removes priority from a user.
```Lua
Queue.RemovePriority("STEAM_0:1:33459672")
```

## IsReady
Will return whether or not the queue's exports are ready to be called.
```Lua
print(Queue.IsReady())
```

## Other Queue Functions
You can call every queue function within sh_queue.lua.
```Lua
local ids = Queue.Exports:GetIds(src)

-- sets the player to position 1 in queue
Queue.Exports:SetPos(ids, 1)
-- returns whether or not the player has any priority
Queue.Exports:IsPriority(ids)
--- returns size of queue
Queue.Exports:GetSize()
-- plus many more...
```