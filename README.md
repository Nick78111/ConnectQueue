# ConnectQueue
Connection queue for FiveM

#ConVars
	set sv_debugqueue true # prints debug messages to console
	set sv_displayqueue true # shows queue count in the server name '[count] server name'

#Events
	AddEventHandler("queue:playerJoinQueue", function(src, setKickReason)
	    setKickReason("No, you can't join")
	    CancelEvent()
	end)

# Exports
Any identifier should work, it will use ip's if it can't find any. There is also support for SteamID32's.

    exports.connectqueue:AddPriority(string id, integer power)
    exports.connectqueue:AddPriority(table ids)
	exports.connectqueue:RemovePriority(string id)
	
# Examples
	exports.queueconnect:AddPriority("steam:110000#####", 50)
	exports.queueconnect:AddPriority("ip:127.0.0.1", 50)
	exports.queueconnect:AddPriority("STEAM_0:1:########", 50)
	
	local prioritize = {
	    ["STEAM_0:1:########"] = 10,
	    ["ip:127.0.0.1"] = 20,
	    ["steam:110000#####"] = 100
	}
	exports.queueconnect:AddPriority(prioritize)
	
	exports.queueconnect:RemovePriority("STEAM_0:1:########")