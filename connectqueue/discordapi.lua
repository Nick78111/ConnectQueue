local discordGuildId = GetConvar('sb:discordGuildId', "")
local FormattedToken = GetConvar('sb:discordBotToken', '')


local error_codes_defined = {
	[200] = 'OK - The request was completed successfully..!',
	[204] = 'OK - No Content',
	[400] = "Error - The request was improperly formatted, or the server couldn't understand it..!",
	[401] =
	'Error - The Authorization header was missing or invalid..! Your Discord Token is probably wrong or does not have correct permissions attributed to it.',
	[403] =
	'Error - The Authorization token you passed did not have permission to the resource..! Your Discord Token is probably wrong or does not have correct permissions attributed to it.',
	[404] = "Error - The resource at the location specified doesn't exist.",
	[429] =
	'Error - Too many requests, you hit the Discord rate limit. https://discord.com/developers/docs/topics/rate-limits',
	[502] = 'Error - Discord API may be down?...'
}

function sendDebugMessage(msg)
	print(msg);
end

function DiscordRequest(method, endpoint, jsondata, reason)
	local data = nil
	PerformHttpRequest("https://discord.com/api/" .. endpoint, function(errorCode, resultData, resultHeaders)
		data = { data = resultData, code = errorCode, headers = resultHeaders }
	end, method, #jsondata > 0 and jsondata or "",
		{ ["Content-Type"] = "application/json", ["Authorization"] = "Bot "..FormattedToken, ['X-Audit-Log-Reason'] = reason })

	while data == nil do
		Citizen.Wait(0)
	end
	return data
end

Caches = {
	RoleList = {}
}
function ResetCaches()
	Caches = {
		RoleList = {},
	};
end

function GetGuildRoleList(guild)
	local guildId = discordGuildId
	if (Caches.RoleList[guildId] == nil) then
		local guild = DiscordRequest("GET", "guilds/" .. guildId, {})
		if guild.code == 200 then
			local data = json.decode(guild.data)
			local roles = data.roles;
			local roleList = {};
			for i = 1, #roles do
				roleList[roles[i].name] = roles[i].id;
			end
			Caches.RoleList[guildId] = roleList;
		else
			sendDebugMessage("An error occured, please check your config and ensure everything is correct. Error: " ..
			(guild.data or guild.code))
			Caches.RoleList[guildId] = nil;
		end
	end
	return Caches.RoleList[guildId];
end

recent_role_cache = {}

function ClearCache(discordId)
	if (discordId ~= nil) then
		recent_role_cache[discordId] = {};
	end
end

function GetDiscordRoles(user)
	local discordId = nil
	local guildId = discordGuildId
	local roles = nil
	for _, id in ipairs(GetPlayerIdentifiers(user)) do
		if string.match(id, "discord:") then
			discordId = string.gsub(id, "discord:", "")
			break;
		end
	end
	if discordId then
		roles = GetUserRolesInGuild(discordId, guildId)
		return roles
	else
		sendDebugMessage("ERROR: Discord was not connected to user's Fivem account...")
		return false
	end
	return false
end

function GetUserRolesInGuild(user, guild)
	if not user then
		sendDebugMessage("ERROR: GetUserRolesInGuild requires discord ID")
		return false
	end
	if not guild then
		sendDebugMessage("ERROR: GetUserRolesInGuild requires guild ID")
		return false
	end
	if recent_role_cache[user] and recent_role_cache[user][guild] then
		return recent_role_cache[user][guild]
	end

	local endpoint = ("guilds/%s/members/%s"):format(guild, user)
	local member = DiscordRequest("GET", endpoint, {})
	if member.code == 200 then
		local data = json.decode(member.data)
		local roles = data.roles
		recent_role_cache[user] = recent_role_cache[user] or {}
		recent_role_cache[user][guild] = roles
		Citizen.SetTimeout((60 * 1000),
			function() recent_role_cache[user][guild] = nil end)
		 
		return roles
	else
		sendDebugMessage("ERROR: Code 200 was not reached... Returning false. [Member Data NOT FOUND] DETAILS: " ..
		error_codes_defined[member.code])
		return false
	end
end


CreateThread(function()
	local mguild = DiscordRequest("GET", "guilds/" .. discordGuildId, {})
	if mguild.code == 200 then
		local data = json.decode(mguild.data)
		sendDebugMessage("Successful connection to Guild : " .. data.name .. " (" .. data.id .. ")")
		-- print(json.encode(GetUserRolesInGuild("759846912387579924", "656158231458218034")))
	else
		sendDebugMessage("An error occured, please check your config and ensure everything is correct. Error: " ..
		(mguild.data and json.decode(mguild.data) or mguild.code))
	end
end)
