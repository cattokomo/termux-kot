local timer = require("timer")
local fs = require("fs")
local json = require("json")

local lpeg = require("lpeg")
local patt_uri = require("lpeg_patterns.uri")

local config = json.decode((assert(fs.readFileSync("config.json"), "cannot find config.json!")))
local status = json.decode((assert(fs.readFileSync("status.json"), "cannot find status.json!")))

---@type discordia
local discordia = require("discordia")
local slash_tools = require("discordia-slash").util.tools()
local ext = discordia.extensions
ext.string()

---@diagnostic disable-next-line:undefined-field
local client = discordia.Client():useApplicationCommands()
---@diagnostic disable-next-line:undefined-field -- discordia meta doesn't support 2.11.0
client:enableIntents(discordia.enums.gatewayIntent.messageContent)

local env = setmetatable({ require = require }, { __index = _G })

local cmds = {}
for path in fs.scandirSync("commands") do
	---@diagnostic disable-next-line:param-type-mismatch
	local cmd, err = load(assert(fs.readFileSync("commands/" .. path)), "@commands/" .. path, "t", env)

	if cmd and not err then
		local cmd_obj = cmd()
		cmd_obj.description = cmd_obj.owner_only and cmd_obj.description .. " (Owner only)" or cmd_obj.description

		cmds[#cmds + 1] = cmd_obj
		client:info("Loaded successfully: %s", path)
	else
		client:error("Failed to load: %s", path)
		client:error(err or "")
	end
end

cmds[#cmds + 1] = {
	name = "help",
	description = "Show message about commands.",
	options = {
		slash_tools.boolean("internal", "Display with also internal commands."):setRequired(false),
	},
	cb = function(ia, args)
		local cmd_helpstr = ""

		for _, v in ipairs(cmds) do
			if not v.internal or v.internal and args.internal then
				cmd_helpstr = cmd_helpstr .. ("%-7s \27[34m.. %s\27[0m\n"):format(v.name, v.description)
			end
		end

		ia:reply({
			content = ("\
\27[31m:: Commands ::\27[0m\n\
%s"):format(cmd_helpstr),
			code = "ansi",
		})
	end,
}

---------------------------------------------------------------------------------

---@cast client Client
---@diagnostic disable:need-check-nil
---@diagnostic disable:undefined-field
client:on("ready", function()
	client:info("Purr~... Watching messages in the server :3")

	math.randomseed(os.time())
	client:setActivity(status[math.random(#status)])
	timer.setInterval(120 * 1000, function()
		math.randomseed(os.time())
		coroutine.wrap(client.setActivity)(client, status[math.random(#status)])
	end)

	for _, cmd_obj in ipairs(cmds) do
		local slash_cmd = slash_tools.slashCommand(cmd_obj.name, cmd_obj.description)
		for _, option in ipairs(cmd_obj.options) do
			slash_cmd:addOption(option)
		end
		client:createGlobalApplicationCommand(slash_cmd)
	end
end)

---@diagnostic disable-next-line:redundant-parameter
client:on("slashCommand", function(ia, cmd, args)
	for _, cmd_obj in ipairs(cmds) do
		if cmd_obj.name == cmd.name then
			if cmd_obj.owner_only and ia.user.id ~= config.ownerid then
				break
			end
			cmd_obj.cb(ia, args or {}, config)
			client:info("%s used /%s command", ia.user.username, cmd.name)
		end
	end
end)

client:on("messageCreate", function(msg)
	if msg.author.bot then
		return
	end

	local showcase_chann = "712954974983684137"
	local modlogs_chann = "810521091973840957"

	if
		msg.channel.id == showcase_chann
		and not (
			msg.content:find("```.+```")
			or msg.attachment
			or lpeg.P({ patt_uri.uri + 1 * lpeg.V(1) }):match(msg.content)
		)
	then
		msg:delete()
		client:info("Caught %s's message!", msg.author.username)

		local bot_msg = msg:reply({
			content = "Please open a thread and talk there meow x3",
			mention = msg.author,
		})
		timer.setTimeout(3000, function()
			coroutine.wrap(bot_msg.delete)(bot_msg)
		end)

		---@diagnostic disable-next-line:redundant-parameter
		local modlogs_textchann = msg.guild.textChannels:find(function(c)
			---@diagnostic disable-next-line:redundant-return-value
			return c.id == modlogs_chann
		end)
		---@cast modlogs_textchann TextChannel

		modlogs_textchann:send({
			embed = {
				author = {
					name = msg.author.name .. "#" .. msg.author.discriminator,
					icon_url = msg.author.avatarURL,
				},
				footer = {
					text = "Author: " .. msg.author.id,
				},
				description = ("**Caught <@%s>'s message!**\n%s"):format(msg.author.id, msg.content),
				color = 0x00cccc,
				timestamp = discordia.Date():toISO("T", "Z"),
			},
		})
	end
end)

client:run("Bot " .. config.token)
