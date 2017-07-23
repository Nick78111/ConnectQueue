# ConnectQueue
Connection queue for FiveM


# Exports

    exports.connectqueue:AddPriority(string id, integer power)
    exports.connectqueue:AddPriority(table ids)
	exports.connectqueue:RemovePriority(string id)
# Example
	exports.connectqueue:AddPriority("STEAM_0:1126554", 50)

	local prioritize = {
		["STEAM_0:11354"] = 10,
		["STEAM_0:1523452] = 20
	}

	exports.connectqueue:AddPriority(priority)

	exports.connectqueue:RemovePriority("STEAM_0:11354")
