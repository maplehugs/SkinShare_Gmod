-- SkinShare: un jugador elige uno de SUS addons de modelos y todos lo descargan y montan en partida.
AddCSLuaFile()
local VERSION = "0.12.0"
print("SkinShare v" .. VERSION)

-- config del server (replicada: el cliente la lee para el menú y para filtrar lo que monta)
local FLAGS = { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }
local CV = {
	enabled = CreateConVar("sv_skinshare_enabled", 1, FLAGS, "Allow SkinShare on this server", 0, 1),
	adminonly = CreateConVar("sv_skinshare_adminonly", 0, FLAGS, "Only admins can share skins", 0, 1),
	cooldown = CreateConVar("sv_skinshare_cooldown", 1, FLAGS, "Seconds between skin changes (admins skip it)", 0, 900),
	maxsize = CreateConVar("sv_skinshare_maxsize", 300, FLAGS, "Max size in MB of a shared addon", 1, 4096),
	gamemodes = CreateConVar("sv_skinshare_block_gamemodes", "", FLAGS, "Comma-separated gamemodes where SkinShare is off, e.g. murder,prop_hunt"),
	addons = CreateConVar("sv_skinshare_block_addons", "", FLAGS, "Comma-separated Workshop IDs that can't be shared"),
}

local function listed(cv, v)
	local l = "," .. cv:GetString():gsub("%s", ""):lower() .. ","
	return l:find("," .. tostring(v):lower() .. ",", 1, true) ~= nil
end

-- nil si el jugador puede usar SkinShare; si no, el motivo (clave de STRINGS).
-- Otros addons/gamemodes pueden bloquearlo: hook.Add("SkinShareCanUse", id, function(ply) return false end)
local function blocked(ply)
	if not CV.enabled:GetBool() or listed(CV.gamemodes, engine.ActiveGamemode()) or hook.Run("SkinShareCanUse", ply) == false then return "blockedOff" end
	if CV.adminonly:GetBool() and not ply:IsAdmin() then return "blockedAdmin" end
	if ply:GetNWBool("skinshare_banned") then return "blockedBan" end
end

local function download(wsid, cb)
	steamworks.DownloadUGC(wsid, function(path)
		if not path then return end
		local ok, files = game.MountGMA(path)
		if ok then cb(files) end
	end)
end

-- nil si se puede compartir; si no, el motivo (clave de STRINGS)
local function rejected(info, wsid)
	if listed(CV.addons, wsid) then return "whyBlocked" end
	if not info then return "whyMissing" end
	if not tostring(info.tags or ""):lower():find("model", 1, true) then return "whyTag" end
	if (tonumber(info.size) or 0) > CV.maxsize:GetInt() * 1048576 then return "whySize" end
end

local function mount(wsid, cb)
	if wsid == "0" then return cb({}) end -- modelo del juego base, todos lo tienen
	if listed(CV.addons, wsid) then return end
	if not steamworks.FileInfo then return download(wsid, cb) end
	-- cualquiera puede pedir una skin: solo se montan items con tag Model y de tamaño razonable,
	-- para que nadie obligue a todos a montar un pack que reemplace texturas o sonidos
	steamworks.FileInfo(wsid, function(info)
		if not rejected(info, wsid) then download(wsid, cb) end
	end)
end

-- "0 2 1" -> {[0]=0, [1]=2, [2]=1}
local function nums(str)
	local t, i = {}, 0
	for v in (str or ""):gmatch("%-?[%d%.]+") do t[i] = tonumber(v) or 0 i = i + 1 end
	return t
end

local MDL = "^models/[%w_%-%./]+%.mdl$"

if SERVER then
	util.AddNetworkString("skinshare")
	util.AddNetworkString("skinshare_ack")
	-- global para que sobreviva si el Lua se recarga en caliente (si no, todos vuelven al modelo default)
	SkinShareSkins = SkinShareSkins or {}
	local skins = SkinShareSkins -- [steamid64] = {wsid, mdl, arms, skin, bg, flex, col, wcol, waiting, ready}

	local function send(ply, s, to)
		net.Start("skinshare")
		net.WriteEntity(ply) net.WriteString(s.wsid) net.WriteString(s.mdl)
		if to then net.Send(to) else net.Broadcast() end
	end

	-- solo se reemplazan playermodels: así Prop Hunt y similares pueden seguir volviéndote un prop
	local function isPlayerModel(m)
		m = m:lower()
		if m:find("/player/", 1, true) then return true end
		for _, v in pairs(player_manager.AllValidModels()) do
			if v:lower() == m then return true end
		end
	end

	local function look(ply, s)
		ply:SetSkin(math.min(s.skin, ply:SkinCount() - 1))
		for i, v in pairs(nums(s.bg)) do ply:SetBodygroup(i, v) end
		for i, v in pairs(nums(s.flex)) do ply:SetFlexWeight(i, math.Clamp(v, -1, 1)) end
	end

	local function active(ply)
		local s = skins[ply:SteamID64()]
		return s and s.ready and file.Exists(s.mdl, "GAME") and s
	end

	-- forzar: cualquier SetModel del gamemode (TTT, etc.) se cambia por la skin elegida
	local meta = FindMetaTable("Player")
	-- SetModel vive en Entity, no en Player
	meta.SkinShareRawSetModel = meta.SkinShareRawSetModel or FindMetaTable("Entity").SetModel
	function meta:SetModel(m)
		local s = active(self)
		if not (s and isstring(m) and (m == s.mdl or isPlayerModel(m))) then
			return self:SkinShareRawSetModel(m)
		end
		self:SkinShareRawSetModel(s.mdl)
		look(self, s)
	end

	local function apply(ply)
		local s = active(ply)
		if not s then return end
		ply:SetModel(s.mdl)
		ply:SetPlayerColor(s.col)
		ply:SetWeaponColor(s.wcol)
		if ply.SetupHands then ply:SetupHands() end
		return true
	end

	-- manos: el cliente manda las de su skin (el Lua que las registra no corre aquí).
	-- Con el hook sirve también cuando el gamemode rearma las manos (respawn, ronda nueva).
	hook.Add("PlayerSetHandsModel", "skinshare", function(ply, ent)
		local s = active(ply)
		if s and s.arms ~= "" and file.Exists(s.arms, "GAME") then
			ent:SetModel(s.arms) ent:SetSkin(0) ent:SetBodyGroups("0000000")
			return true
		end
	end)

	-- vuelve a la skin y colores del gamemode
	local function strip(ply)
		if not skins[ply:SteamID64()] then return end
		skins[ply:SteamID64()] = nil
		timer.Remove("skinshare_" .. ply:SteamID64())
		-- cl_playercolor solo existe en Sandbox; antes del gamemode para que TTT ponga los suyos
		local pc, wc = ply:GetInfo("cl_playercolor"), ply:GetInfo("cl_weaponcolor")
		if pc ~= "" then ply:SetPlayerColor(Vector(pc)) end
		if wc ~= "" then ply:SetWeaponColor(Vector(wc)) end
		if ply:Alive() and GAMEMODE.PlayerSetModel then GAMEMODE:PlayerSetModel(ply) end
		if ply.SetupHands then ply:SetupHands() end
		send(ply, { wsid = "none", mdl = "" })
	end

	-- si un admin apaga SkinShare, bloquea el gamemode o un addon, se quitan al momento las skins afectadas
	local function recheck()
		for _, p in ipairs(player.GetAll()) do
			local s = skins[p:SteamID64()]
			if s and (blocked(p) or listed(CV.addons, s.wsid)) then strip(p) end
		end
	end
	for _, k in ipairs({ "enabled", "adminonly", "gamemodes", "addons" }) do
		cvars.AddChangeCallback(CV[k]:GetName(), function() timer.Simple(0, recheck) end, "skinshare")
	end

	local function color(v)
		return Vector(math.Clamp(v.x, 0, 1), math.Clamp(v.y, 0, 1), math.Clamp(v.z, 0, 1))
	end

	-- cada cliente avisa cuando ya montó la skin; si el server la pone antes, ese cliente la cachea como ERROR
	net.Receive("skinshare_ack", function(_, from)
		local owner, mdl = net.ReadEntity(), net.ReadString()
		local s = IsValid(owner) and skins[owner:SteamID64()]
		if s and s.mdl == mdl then s.waiting[from] = nil end
	end)

	local function allMounted(s)
		for p in pairs(s.waiting) do
			if IsValid(p) and not p:IsBot() then return false end
		end
		return true
	end

	net.Receive("skinshare", function(_, ply)
		local wsid = net.ReadString()

		if wsid == "" then -- recién conectado: mándale las skins actuales
			for _, p in ipairs(player.GetAll()) do
				local s = skins[p:SteamID64()]
				if s then send(p, s, ply) end
			end
			return
		end

		if wsid == "none" then return strip(ply) end -- quitarse la skin siempre se puede
		if blocked(ply) or listed(CV.addons, wsid) then return end

		if (ply.skinshareNext or 0) > CurTime() then
			ply:ChatPrint("SkinShare: too fast, wait a moment and try again.")
			return
		end
		if not ply:IsAdmin() then ply.skinshareNext = CurTime() + CV.cooldown:GetFloat() end

		local mdl, arms, skin, bg, flex = net.ReadString(), net.ReadString(), net.ReadUInt(8), net.ReadString(), net.ReadString()
		local col, wcol = color(net.ReadVector()), color(net.ReadVector())
		if not wsid:match("^%d+$") or not mdl:match(MDL) or mdl:find("..", 1, true) then return end
		if arms ~= "" and (not arms:match(MDL) or arms:find("..", 1, true)) then arms = "" end
		if #bg > 255 or not bg:match("^[%d ]*$") then return end
		if #flex > 8192 or not flex:match("^[%d%.%- ]*$") then return end

		local s = { wsid = wsid, mdl = mdl, arms = arms, skin = skin, bg = bg, flex = flex, col = col, wcol = wcol, waiting = {} }
		for _, p in ipairs(player.GetAll()) do s.waiting[p] = true end
		skins[ply:SteamID64()] = s
		send(ply, s)
		-- los que se unan después la descargan mientras conectan
		if wsid ~= "0" then resource.AddWorkshop(wsid) end
		-- listen server: el cliente del host monta el GMA y comparte filesystem con el server
		if game.IsDedicated() and steamworks.DownloadUGC then mount(wsid, function() end) end

		-- se aplica cuando todos la montaron, o a los 60 s aunque alguien siga descargando
		local name = "skinshare_" .. ply:SteamID64()
		timer.Create(name, 1, 60, function()
			if not IsValid(ply) or skins[ply:SteamID64()] ~= s then return timer.Remove(name) end
			s.tries = (s.tries or 0) + 1
			if allMounted(s) or s.tries >= 60 then
				s.ready = true
				if apply(ply) then timer.Remove(name) end
			end
		end)
	end)

	-- después del gamemode (TTT/Sandbox ponen modelo y color en PlayerSpawn)
	hook.Add("PlayerSpawn", "skinshare", function(ply)
		timer.Simple(0, function() if IsValid(ply) then apply(ply) end end)
	end)

	-- TTT repone el color al empezar cada ronda sin respawnear (SpawnForRound)
	hook.Add("TTTPlayerSetColor", "skinshare", function(ply)
		local s = active(ply)
		if s then ply:SetPlayerColor(s.col) return true end
	end)

	-- en el server, antes que el gamemode: Murder reenvía el chat de los vivos y en el cliente nunca llega como chat normal
	hook.Add("PlayerSay", "skinshare", function(ply, text)
		local t = text:lower():Trim()
		if t == "!skin" or t == "/skin" then ply:ConCommand("skinshare") return "" end
	end)

	hook.Add("PlayerDisconnected", "skinshare", function(ply) skins[ply:SteamID64()] = nil end)

	-- baneo persistente (PData); el NWBool deja que el cliente explique por qué no puede
	hook.Add("PlayerInitialSpawn", "skinshare", function(ply)
		ply:SetNWBool("skinshare_banned", ply:GetPData("skinshare_banned") == "1")
	end)

	local function findPlayer(q)
		q = q:lower()
		for _, p in ipairs(player.GetAll()) do
			if p:SteamID64() == q or p:SteamID():lower() == q then return p end
		end
		for _, p in ipairs(player.GetAll()) do
			if p:Nick():lower():find(q, 1, true) then return p end
		end
	end

	-- skinshare_admin set <setting> <value> | strip|ban|unban <name|steamid> | blockaddon <wsid>
	-- desde la consola del server, RCON o un admin (el panel Admin del menú usa esto)
	concommand.Add("skinshare_admin", function(ply, _, args)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local function say(msg) if IsValid(ply) then ply:ChatPrint("[SkinShare] " .. msg) else print("[SkinShare] " .. msg) end end
		local action, target, value = args[1] or "", args[2] or "", args[3] or ""
		if action == "set" then
			if CV[target] then CV[target]:SetString(value:sub(1, 1024)) end
		elseif action == "blockaddon" then
			if target:match("^%d+$") and not listed(CV.addons, target) then
				local cur = CV.addons:GetString()
				CV.addons:SetString(cur == "" and target or cur .. "," .. target)
			end
		elseif action == "strip" or action == "ban" or action == "unban" then
			local p = findPlayer(target)
			if not IsValid(p) then return say("player not found: " .. target) end
			if action ~= "strip" then
				local ban = action == "ban"
				if ban then p:SetPData("skinshare_banned", "1") else p:RemovePData("skinshare_banned") end
				p:SetNWBool("skinshare_banned", ban)
			end
			if action ~= "unban" then strip(p) end
			say(action .. ": " .. p:Nick())
		else
			say("usage: skinshare_admin set <setting> <value> | strip|ban|unban <name|steamid> | blockaddon <wsid>")
		end
	end)
	return
end

-- data/skinshare.json: { last = config, favs = { {name = ..., cfg = config}, ... } }
local DATA = "skinshare.json"
local function loadData()
	local d = util.JSONToTable(file.Read(DATA, "DATA") or "") or {}
	if not istable(d.favs) or d.favs[1] == nil then d.favs = {} end -- formato viejo (por nombre) se descarta
	return d
end
local function saveData(d) file.Write(DATA, util.TableToJSON(d, true)) end

local function choose(c)
	net.Start("skinshare") net.WriteString(c.wsid)
	if c.mdl then
		net.WriteString(c.mdl) net.WriteString(c.arms or "") net.WriteUInt(c.skin, 8)
		net.WriteString(c.bg) net.WriteString(c.flex) net.WriteVector(c.col) net.WriteVector(c.wcol)
	end
	net.SendToServer()
end

local others = {} -- [jugador] = {wsid, mdl}, para el panel Admin
net.Receive("skinshare", function()
	local ply, wsid, mdl = net.ReadEntity(), net.ReadString(), net.ReadString()
	if wsid == "none" then others[ply] = nil return end
	others[ply] = { wsid = wsid, mdl = mdl }
	mount(wsid, function()
		net.Start("skinshare_ack") net.WriteEntity(ply) net.WriteString(mdl) net.SendToServer()
		if IsValid(ply) then ply:SetModel(mdl) end
	end)
end)

hook.Add("InitPostEntity", "skinshare", function()
	choose({ wsid = "" })
	local last = loadData().last -- vuelve a ponerte tu última skin al entrar
	if last and last.mdl then choose(last) end
end)

-- mismo truco que duplicator.FigureOutRequiredAddons
local function addonFor(mdl)
	for _, a in ipairs(engine.GetAddons()) do
		if a.mounted and file.Exists(mdl, a.title) then return tostring(a.wsid) end
	end
	return "0"
end

-- brazos del viewmodel para skins cuyo Lua no corre aquí: <modelo>_arms.mdl o c_arms*.mdl de su mismo addon
local function armsFor(mdl, wsid)
	-- registrado por el Lua del addon (solo corrió en este cliente, el server no lo conoce): sus manos
	for name, v in pairs(player_manager.AllValidModels()) do
		if v:lower() == mdl then
			local info = player_manager.TranslatePlayerHands(name)
			if info and info.model and info.model ~= "models/weapons/c_arms_citizen.mdl" then return info.model:lower() end
			break
		end
	end
	local arms = string.StripExtension(mdl) .. "_arms.mdl"
	if file.Exists(arms, "GAME") then return arms end
	for _, a in ipairs(engine.GetAddons()) do
		if tostring(a.wsid) == wsid then
			local dir = string.GetPathFromFilename(mdl)
			local found = file.Find(dir .. "c_arms*.mdl", a.title)
			return found and found[1] and (dir .. found[1]):lower() or ""
		end
	end
	return ""
end

-- Un playermodel incluye las animaciones de jugador (models/m_anm.mdl, f_anm o z_anm); brazos y props no.
local isPM = {} -- caché por sesión
local function isPlayerModel(p)
	if isPM[p] == nil then
		local fh = file.Open(p, "rb", "GAME")
		-- ponytail: lee el .mdl entero; la primera vez tarda si hay packs con miles de props
		local data = fh and fh:Size() > 0 and fh:Read(fh:Size()) or ""
		if fh then fh:Close() end
		isPM[p] = data:lower():find("models/[mfz]_anm%.mdl") ~= nil
	end
	return isPM[p]
end

-- En server ajeno el cliente no corre el Lua de SUS addons, así que sus playermodels no se registran
-- en player_manager. Se buscan los .mdl directamente en sus addons montados.
local function findModels(dir, path, out)
	local files, dirs = file.Find(dir .. "*", path)
	for _, f in ipairs(files or {}) do
		local p = (dir .. f):lower()
		if p:sub(-4) == ".mdl" and isPlayerModel(p) then
			out[p] = path .. " / " .. string.StripExtension(f)
		end
	end
	for _, d in ipairs(dirs or {}) do findModels(dir .. d .. "/", path, out) end
end

local function allModels()
	local list = {} -- [mdl] = nombre
	for _, a in ipairs(engine.GetAddons()) do
		if a.mounted and (a.models or 1) > 0 then findModels("models/", a.title, list) end
	end
	for name, mdl in pairs(player_manager.AllValidModels()) do list[mdl:lower()] = name end
	return list
end

concommand.Add("skinshare_debug", function()
	print("SkinShare v" .. VERSION)
	for _, a in ipairs(engine.GetAddons()) do
		local f, d = file.Find("models/*", a.title)
		if #(f or {}) + #(d or {}) > 0 then print(a.mounted, a.wsid, a.models, #f + #d, a.title) end
	end
end)

-- idioma: auto sigue el idioma de GMod (gmod_language); skinshare_language en/es lo fuerza
local LANG = CreateClientConVar("skinshare_language", "auto", true, false, "auto, en or es")
local STRINGS = {
	en = { search = "Search...", models = "Models", favorites = "Favorites", bodygroups = "Bodygroups",
		face = "Face", colors = "Colors", playercolor = "Player color", weaponcolor = "Weapon color (physgun, etc.)",
		delete = "Delete", load = "Load", favorite = "Favorite", namePrompt = "Name:", rename = "Rename",
		addFav = "Add to favorites", select = "Select", rebuild = "Rebuild icon", overwrite = "Overwrite with current", noFavs = "Right-click a model to add it here.",
		hint = "Drag: rotate   Wheel: zoom   Right-click: favorite",
		remove = "Remove skin", reset = "Reset", apply = "Use and share",
		cantShare = "Other players can't download this skin: ", whyMissing = "the addon is private, hidden or doesn't exist.",
		whyTag = "the addon isn't tagged \"Model\" on the Workshop.", whySize = "the addon is bigger than %d MB.",
		whyBlocked = "the server blocked this addon.", blockedOff = "SkinShare is disabled on this server or gamemode.",
		blockedAdmin = "Only admins can use SkinShare on this server.", blockedBan = "You're banned from SkinShare on this server.",
		copyPath = "Copy model path", rescan = "Rescan models", random = "Random model", noFavsRandom = "You have no favorites yet.",
		admin = "Admin", aEnabled = "SkinShare enabled", aAdminOnly = "Only admins can use it", aCooldown = "Cooldown between changes (s)",
		aMaxSize = "Max addon size (MB)", aGamemodes = "Blocked gamemodes (comma-separated, Enter to save)", aBlockGM = "Block current gamemode",
		aAddons = "Blocked addons (Workshop IDs, comma-separated, Enter to save)", aPlayers = "Players (click for actions)",
		aStrip = "Remove their skin", aBlockAddon = "Block this addon", aBan = "Ban from SkinShare", aUnban = "Unban",
		aCopySID = "Copy SteamID", aNoSkin = "no skin", aBanned = "BANNED" },
	es = { search = "Buscar...", models = "Modelos", favorites = "Favoritos", bodygroups = "Bodygroups",
		face = "Cara", colors = "Colores", playercolor = "Color del jugador", weaponcolor = "Color del arma (physgun, etc.)",
		delete = "Borrar", load = "Cargar", favorite = "Favorito", namePrompt = "Nombre:", rename = "Renombrar",
		addFav = "Agregar a favoritos", select = "Seleccionar", rebuild = "Regenerar ícono", overwrite = "Sobrescribir con el actual", noFavs = "Clic derecho en un modelo para agregarlo aquí.",
		hint = "Arrastra: girar   Rueda: zoom   Clic derecho: favorito",
		remove = "Quitar skin", reset = "Reiniciar", apply = "Usar y compartir",
		cantShare = "Los demás no pueden descargar esta skin: ", whyMissing = "el addon es privado, está oculto o no existe.",
		whyTag = "el addon no tiene el tag \"Model\" en el Workshop.", whySize = "el addon pesa más de %d MB.",
		whyBlocked = "el server bloqueó este addon.", blockedOff = "SkinShare está desactivado en este server o modo de juego.",
		blockedAdmin = "En este server solo los admins pueden usar SkinShare.", blockedBan = "Estás baneado de SkinShare en este server.",
		copyPath = "Copiar ruta del modelo", rescan = "Reescanear modelos", random = "Modelo aleatorio", noFavsRandom = "Todavía no tienes favoritos.",
		admin = "Admin", aEnabled = "SkinShare activado", aAdminOnly = "Solo los admins pueden usarlo", aCooldown = "Espera entre cambios (s)",
		aMaxSize = "Tamaño máximo del addon (MB)", aGamemodes = "Modos bloqueados (separados por coma, Enter para guardar)", aBlockGM = "Bloquear el modo actual",
		aAddons = "Addons bloqueados (IDs del Workshop, separados por coma, Enter para guardar)", aPlayers = "Jugadores (clic para acciones)",
		aStrip = "Quitarle la skin", aBlockAddon = "Bloquear este addon", aBan = "Banear de SkinShare", aUnban = "Desbanear",
		aCopySID = "Copiar SteamID", aNoSkin = "sin skin", aBanned = "BANEADO" },
}
local function lang()
	local l = LANG:GetString()
	if l == "auto" then l = GetConVar("gmod_language"):GetString():sub(1, 2) end
	return STRINGS[l] and l or "en"
end
local function T(key) return STRINGS[lang()][key] end

local function warn(msg) chat.AddText(Color(255, 90, 90), "[SkinShare] ", color_white, msg) end

-- elegir y compartir una skin (menú, favoritos, aleatoria): avisa si el server no deja o si los demás no podrán bajarla
local function share(c)
	local why = blocked(LocalPlayer())
	if why then return warn(T(why)) end
	choose(c)
	if c.wsid ~= "0" and steamworks.FileInfo then
		steamworks.FileInfo(c.wsid, function(info)
			why = rejected(info, c.wsid)
			if why then warn(T("cantShare") .. T(why):format(CV.maxsize:GetInt())) end
		end)
	end
end

local function slider(parent, label, min, max, decimals, val, onChange)
	local s = parent:Add("DNumSlider")
	s:Dock(TOP) s:SetText(label) s:SetDark(true) s:SetDecimals(decimals) s:SetMinMax(min, max) s:SetValue(val)
	s.OnValueChanged = function(_, v) onChange(decimals == 0 and math.Round(v) or v) end
end

-- skin plano oscuro para toda la ventana (botones, pestañas, sliders, scroll, menús).
local ACCENT, ACCENT_HI = Color(60, 150, 245), Color(90, 175, 255)
local BG, BG_PREVIEW = Color(24, 26, 31), Color(36, 39, 46)
local SURFACE, SURFACE_HI, SURFACE_LO = Color(44, 47, 55), Color(58, 62, 72), Color(32, 34, 40)
local TEXT, TEXT_DIM = Color(230, 232, 236), Color(150, 155, 165)

local SKIN = { PrintName = "SkinShare", Author = "SkinShare", DermaVersion = 1 } -- DefineSkin hereda de Default
SKIN.colTextEntryText, SKIN.colTextEntryTextPlaceholder = TEXT, TEXT_DIM
SKIN.colTextEntryTextHighlight, SKIN.colTextEntryTextCursor = ACCENT, TEXT
SKIN.colNumSliderNotch = Color(255, 255, 255, 40)
local function states(n, h, d, x) return { Normal = n, Hover = h, Down = d, Disabled = x } end
SKIN.Colours = {
	Window = { TitleActive = TEXT, TitleInactive = TEXT_DIM },
	Button = states(TEXT, color_white, color_white, Color(110, 114, 122)),
	Tab = { Active = states(color_white, color_white, color_white, TEXT_DIM), Inactive = states(TEXT_DIM, TEXT, TEXT, Color(90, 94, 102)) },
	Label = { Default = TEXT, Bright = color_white, Dark = TEXT, Highlight = ACCENT_HI },
}
setmetatable(SKIN.Colours, { __index = function(_, k) return derma.GetNamedSkin("Default").Colours[k] end })

function SKIN:PaintFrame(_, w, h)
	draw.RoundedBox(8, 0, 0, w, h, BG)
	draw.RoundedBoxEx(8, 0, 0, w, 24, Color(16, 17, 21), true, true)
	surface.SetDrawColor(ACCENT) surface.DrawRect(0, 24, w, 2)
end
function SKIN:PaintPanel(p, w, h) if p.m_bBackground then draw.RoundedBox(6, 0, 0, w, h, SURFACE_LO) end end
function SKIN:PaintButton(p, w, h)
	if not p.m_bBackground then return end
	draw.RoundedBox(4, 0, 0, w, h, not p:IsEnabled() and SURFACE_LO or p.Depressed and SURFACE_LO or p.Hovered and SURFACE_HI or SURFACE)
end
function SKIN:PaintWindowCloseButton(p, w, h)
	if p.Hovered then draw.RoundedBox(4, 4, 2, w - 8, h - 6, Color(200, 60, 60)) end
	draw.SimpleText("✕", "DermaDefaultBold", w / 2, h / 2 - 2, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
function SKIN:PaintWindowMinimizeButton() end
function SKIN:PaintWindowMaximizeButton() end
function SKIN:PaintPropertySheet(p, w, h)
	local tab = p:GetActiveTab()
	local y = tab and tab:GetTall() - 8 or 0
	draw.RoundedBox(6, 0, y, w, h - y, SURFACE_LO)
end
function SKIN:PaintTab(p, w, h)
	if p:IsActive() then
		draw.RoundedBoxEx(6, 0, 0, w, h - 8, SURFACE_LO, true, true)
		surface.SetDrawColor(ACCENT) surface.DrawRect(4, 0, w - 8, 2)
	elseif p.Hovered then
		draw.RoundedBoxEx(6, 0, 2, w, h - 10, SURFACE, true, true)
	end
end
function SKIN:PaintTextEntry(p, w, h)
	if p.m_bBackground then
		draw.RoundedBox(4, 0, 0, w, h, p:HasFocus() and ACCENT or SURFACE_HI)
		draw.RoundedBox(4, 1, 1, w - 2, h - 2, SURFACE)
	end
	local empty = p:GetText() == ""
	if empty and (p:GetPlaceholderText() or "") ~= "" then
		p:SetText(p:GetPlaceholderText())
		p:DrawTextEntryText(p:GetPlaceholderColor(), p:GetHighlightColor(), p:GetCursorColor())
		p:SetText("")
	else
		p:DrawTextEntryText(p:GetTextColor(), p:GetHighlightColor(), p:GetCursorColor())
	end
end
function SKIN:PaintVScrollBar(_, w, h) draw.RoundedBox(4, w / 2 - 3, 0, 6, h, SURFACE_LO) end
function SKIN:PaintScrollBarGrip(p, w, h) draw.RoundedBox(4, w / 2 - 3, 0, 6, h, (p.Hovered or p.Depressed) and ACCENT or SURFACE_HI) end
function SKIN:PaintButtonUp() end
function SKIN:PaintButtonDown() end
function SKIN:PaintNumSlider(_, w, h) draw.RoundedBox(2, 8, h / 2 - 2, w - 16, 4, SURFACE_HI) end
function SKIN:PaintSliderKnob(p, w, h)
	draw.RoundedBox(w / 2, 1, 1, w - 2, h - 2, (p.Hovered or p.Depressed) and ACCENT_HI or ACCENT)
end
function SKIN:PaintCheckBox(p, w, h)
	draw.RoundedBox(4, 0, 0, w, h, SURFACE_HI)
	if p:GetChecked() then draw.RoundedBox(3, 3, 3, w - 6, h - 6, ACCENT) end
end
function SKIN:PaintMenu(_, w, h) draw.RoundedBox(4, 0, 0, w, h, SURFACE) end
function SKIN:PaintMenuSpacer(_, w, h) surface.SetDrawColor(SURFACE_HI) surface.DrawRect(4, 0, w - 8, h) end
function SKIN:PaintMenuOption(p, w, h) if p.Hovered then draw.RoundedBox(4, 2, 1, w - 4, h - 2, ACCENT) end end
function SKIN:PaintTooltip(_, w, h) draw.RoundedBox(4, 0, 0, w, h, SURFACE_HI) end
derma.DefineSkin("SkinShare", "Flat dark", SKIN)

local function menu(options) -- { {text, icon, fn}, ... }; false = separador
	local m = DermaMenu()
	for _, o in ipairs(options) do
		if o then m:AddOption(o[1], o[3]):SetIcon(o[2]) else m:AddSpacer() end
	end
	m:SetSkin("SkinShare") m:Open()
end

local function button(parent, text, dock, onClick)
	local b = parent:Add("DButton")
	b:Dock(dock) b:DockMargin(2, 0, 2, 0) b:SetText(text) b.DoClick = onClick
	if dock ~= FILL then b:SetWide(110) end
	return b
end

-- interfaz al estilo Enhanced PlayerModel Selector: preview a la izquierda, pestañas a la derecha
concommand.Add("skinshare", function()
	local me = LocalPlayer()
	local why = blocked(me)
	if why and not me:IsAdmin() then return warn(T(why)) end -- el admin entra igual para poder reactivarlo
	local data = loadData()
	local f = vgui.Create("DFrame")
	f:SetSize(math.min(ScrW() - 16, 960), math.min(ScrH() - 16, 700)) f:Center()
	f:SetTitle("SkinShare v" .. VERSION) f:MakePopup()
	f:DockPadding(8, 32, 8, 8) f:SetSkin("SkinShare")

	local right = f:Add("DPanel")
	right:Dock(RIGHT) right:SetWide(f:GetWide() * 0.45) right:SetPaintBackground(false)
	local bar = right:Add("DPanel")
	bar:Dock(BOTTOM) bar:SetTall(34) bar:DockPadding(0, 4, 0, 0) bar:SetPaintBackground(false)
	local sheet = right:Add("DPropertySheet")
	sheet:Dock(FILL)

	-- Modelos
	local models = vgui.Create("DPanel")
	models:SetPaintBackground(false)
	local searchRow = models:Add("DPanel")
	searchRow:Dock(TOP) searchRow:DockMargin(0, 0, 0, 6) searchRow:SetTall(26) searchRow:SetPaintBackground(false)
	local rescan = searchRow:Add("DButton")
	rescan:Dock(RIGHT) rescan:DockMargin(4, 0, 0, 0) rescan:SetWide(26) rescan:SetText("") rescan:SetImage("icon16/arrow_refresh.png") rescan:SetTooltip(T("rescan"))
	local search = searchRow:Add("DTextEntry")
	search:Dock(FILL) search:SetPlaceholderText(T("search")) search:SetUpdateOnType(true)
	local scroll = models:Add("DScrollPanel")
	scroll:Dock(FILL)
	local grid = scroll:Add("DIconLayout")
	grid:Dock(TOP) grid:SetSpaceX(4) grid:SetSpaceY(4)
	sheet:AddSheet(T("models"), models, "icon16/user.png")

	-- Favoritos: cuadrícula como la de modelos, clic carga, clic derecho renombra/borra
	local favs = vgui.Create("DScrollPanel")
	local noFavs = favs:Add("DLabel")
	noFavs:Dock(TOP) noFavs:DockMargin(8, 8, 8, 0) noFavs:SetText(T("noFavs")) noFavs:SetDark(true)
	local favGrid = favs:Add("DIconLayout")
	favGrid:Dock(TOP) favGrid:DockMargin(4, 4, 4, 4) favGrid:SetSpaceX(4) favGrid:SetSpaceY(4)
	sheet:AddSheet(T("favorites"), favs, "icon16/star.png")

	-- Bodygroups, skin y caras
	local bgPanel = vgui.Create("DScrollPanel")
	bgPanel:DockPadding(8, 8, 8, 8)
	local bgTab = sheet:AddSheet(T("bodygroups"), bgPanel, "icon16/group.png").Tab
	local flexPanel = vgui.Create("DScrollPanel")
	flexPanel:DockPadding(8, 8, 8, 8)
	local flexTab = sheet:AddSheet(T("face"), flexPanel, "icon16/emoticon_wink.png").Tab

	-- Colores
	local colors = vgui.Create("DPanel")
	colors:SetPaintBackground(false)
	local function mixer(label, vec)
		local l = colors:Add("DLabel")
		l:Dock(TOP) l:DockMargin(8, 8, 8, 0) l:SetText(label) l:SetDark(true)
		local m = colors:Add("DColorMixer")
		m:Dock(TOP) m:DockMargin(8, 4, 8, 0) m:SetTall(180) m:SetAlphaBar(false) m:SetPalette(false) m:SetVector(vec)
		return m
	end
	local pcol = mixer(T("playercolor"), me:GetPlayerColor())
	local wcol = mixer(T("weaponcolor"), me:GetWeaponColor())
	sheet:AddSheet(T("colors"), colors, "icon16/color_wheel.png")

	-- Admin: config del server y jugadores; todo pasa por skinshare_admin, que el server valida
	if me:IsAdmin() then
		local adm = vgui.Create("DScrollPanel")
		local function set(k, v)
			timer.Create("skinshare_set_" .. k, 0.3, 1, function() RunConsoleCommand("skinshare_admin", "set", k, tostring(v)) end)
		end
		local function label(text)
			local l = adm:Add("DLabel")
			l:Dock(TOP) l:DockMargin(8, 12, 8, 2) l:SetText(text) l:SetDark(true) l:SetFont("DermaDefaultBold")
		end
		local function check(k, text)
			local c = adm:Add("DCheckBoxLabel")
			c:Dock(TOP) c:DockMargin(8, 8, 8, 0) c:SetText(text) c:SetDark(true) c:SetValue(CV[k]:GetBool())
			c.OnChange = function(_, v) set(k, v and 1 or 0) end
		end
		local function entry(k, text)
			label(text)
			local e = adm:Add("DTextEntry")
			e:Dock(TOP) e:DockMargin(8, 0, 8, 0) e:SetTall(24) e:SetValue(CV[k]:GetString())
			e.OnEnter = function(s) set(k, s:GetValue()) end
			return e
		end
		check("enabled", T("aEnabled"))
		check("adminonly", T("aAdminOnly"))
		slider(adm, T("aCooldown"), 0, 60, 0, CV.cooldown:GetInt(), function(v) set("cooldown", v) end)
		slider(adm, T("aMaxSize"), 10, 2048, 0, CV.maxsize:GetInt(), function(v) set("maxsize", v) end)
		for _, c in ipairs(adm:GetCanvas():GetChildren()) do c:DockMargin(8, 4, 8, 0) end
		local gms = entry("gamemodes", T("aGamemodes"))
		local blockGM = adm:Add("DButton")
		blockGM:Dock(TOP) blockGM:DockMargin(8, 4, 8, 0) blockGM:SetTall(24) blockGM:SetText(T("aBlockGM") .. " (" .. engine.ActiveGamemode() .. ")")
		blockGM.DoClick = function()
			if listed(CV.gamemodes, engine.ActiveGamemode()) then return end
			local v = gms:GetValue():gsub("%s", "")
			v = v == "" and engine.ActiveGamemode() or v .. "," .. engine.ActiveGamemode()
			gms:SetValue(v) set("gamemodes", v)
		end
		local addonsEntry = entry("addons", T("aAddons"))

		label(T("aPlayers"))
		local rows = adm:Add("DPanel")
		rows:Dock(TOP) rows:DockMargin(8, 0, 8, 8) rows:SetPaintBackground(false)
		local function refreshPlayers()
			if not IsValid(rows) then return end
			rows:Clear()
			for _, p in ipairs(player.GetAll()) do
				local o = others[p]
				local b = rows:Add("DButton")
				b:Dock(TOP) b:DockMargin(0, 0, 0, 2) b:SetTall(24) b:SetContentAlignment(4) b:SetTextInset(8, 0)
				b:SetText(p:Nick() .. "   ·   " .. (o and string.StripExtension(string.GetFileFromFilename(o.mdl)) or T("aNoSkin"))
					.. (p:GetNWBool("skinshare_banned") and "   [" .. T("aBanned") .. "]" or ""))
				local sid = p:SteamID64() or ""
				local function run(...) RunConsoleCommand("skinshare_admin", ...) timer.Simple(0.5, refreshPlayers) end
				b.DoClick = function()
					local opts = { { T("aStrip"), "icon16/user_delete.png", function() run("strip", sid) end } }
					if o and o.wsid ~= "0" then
						opts[#opts + 1] = { T("aBlockAddon") .. " (" .. o.wsid .. ")", "icon16/shield.png", function()
							run("blockaddon", o.wsid)
							local cur = addonsEntry:GetValue()
							addonsEntry:SetValue(cur == "" and o.wsid or cur .. "," .. o.wsid)
						end }
					end
					opts[#opts + 1] = false
					if p:GetNWBool("skinshare_banned") then
						opts[#opts + 1] = { T("aUnban"), "icon16/accept.png", function() run("unban", sid) end }
					else
						opts[#opts + 1] = { T("aBan"), "icon16/cancel.png", function() run("ban", sid) end }
					end
					opts[#opts + 1] = { T("aCopySID"), "icon16/page_copy.png", function() SetClipboardText(p:SteamID()) end }
					menu(opts)
				end
				b.DoRightClick = b.DoClick
			end
			rows:SetTall(#player.GetAll() * 26)
		end
		refreshPlayers()
		sheet:AddSheet(T("admin"), adm, "icon16/shield.png")
	end

	-- preview: arrastra para girar, rueda para zoom
	local preview = f:Add("DModelPanel")
	preview:Dock(FILL) preview:DockMargin(0, 0, 8, 0) preview:SetFOV(36) preview:SetAnimated(true)
	preview:SetCamPos(Vector(0, 0, 0)) preview:SetLookAt(Vector(-100, 0, -22))
	local yaw, zoom = 0, 0
	function preview:DragMousePress(code) if code == MOUSE_LEFT then self.px = gui.MouseX() end end
	function preview:DragMouseRelease() self.px = nil end
	function preview:OnMouseWheeled(d) zoom = math.Clamp(zoom + d * 8, -80, 60) end
	function preview:LayoutEntity(ent)
		self:RunAnimation()
		if self.px then yaw = yaw + gui.MouseX() - self.px self.px = gui.MouseX() end
		ent:SetAngles(Angle(0, yaw, 0))
		ent:SetPos(Vector(-100 + zoom, 0, -61))
	end

	local list = allModels()
	local sel = {}
	local basePaint = preview.Paint
	function preview:Paint(w, h)
		draw.RoundedBox(8, 0, 0, w, h, BG_PREVIEW)
		basePaint(self, w, h)
		draw.SimpleText(T("hint"), "DermaDefault", 10, 8, Color(255, 255, 255, 110))
		if sel.mdl then
			draw.SimpleTextOutlined(list[sel.mdl] or string.StripExtension(string.GetFileFromFilename(sel.mdl)), "DermaLarge",
				w / 2, h - 12, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 160))
		end
	end

	local function pick(mdl, skin, bg, flex)
		mdl = mdl:lower()
		preview:SetModel(mdl)
		local ent = preview.Entity
		if not IsValid(ent) then sel = {} return end
		sel = { mdl = mdl, skin = skin or 0, bg = bg or {}, flex = flex or {} }
		ent.GetPlayerColor = function() return pcol:GetVector() end
		local seq = ent:LookupSequence("idle_all_01")
		if seq > 0 then ent:ResetSequence(seq) end

		bgPanel:Clear()
		ent:SetSkin(sel.skin)
		if ent:SkinCount() > 1 then
			slider(bgPanel, "Skin", 0, ent:SkinCount() - 1, 0, sel.skin, function(v) sel.skin = v ent:SetSkin(v) end)
		end
		for i = 0, ent:GetNumBodyGroups() - 1 do
			sel.bg[i] = sel.bg[i] or 0
			ent:SetBodygroup(i, sel.bg[i])
			if ent:GetBodygroupCount(i) > 1 then
				slider(bgPanel, ent:GetBodygroupName(i), 0, ent:GetBodygroupCount(i) - 1, 0, sel.bg[i], function(v) sel.bg[i] = v ent:SetBodygroup(i, v) end)
			end
		end

		flexPanel:Clear()
		for i = 0, ent:GetFlexNum() - 1 do
			sel.flex[i] = sel.flex[i] or 0
			ent:SetFlexWeight(i, sel.flex[i])
			local lo, hi = ent:GetFlexBounds(i)
			slider(flexPanel, ent:GetFlexName(i), lo, hi, 2, sel.flex[i], function(v) sel.flex[i] = v ent:SetFlexWeight(i, v) end)
		end

		bgTab:SetVisible(#bgPanel:GetCanvas():GetChildren() > 0)
		flexTab:SetVisible(ent:GetFlexNum() > 0)
		sheet.tabScroller:InvalidateLayout(true)
	end

	local function current()
		local ent = preview.Entity
		local bg, fl = {}, {}
		for i = 0, ent:GetNumBodyGroups() - 1 do bg[#bg + 1] = sel.bg[i] or 0 end
		for i = 0, ent:GetFlexNum() - 1 do fl[#fl + 1] = string.format("%.2f", sel.flex[i] or 0) end
		local wsid = addonFor(sel.mdl)
		return { wsid = wsid, mdl = sel.mdl, arms = armsFor(sel.mdl, wsid), skin = sel.skin,
			bg = table.concat(bg, " "), flex = table.concat(fl, " "), col = pcol:GetVector(), wcol = wcol:GetVector() }
	end

	local function load(c)
		pcol:SetVector(c.col) wcol:SetVector(c.wcol)
		pick(c.mdl, c.skin, nums(c.bg), nums(c.flex))
	end

	-- no util.IsValidModel: en cliente rechaza todo lo que el server no precacheó (las skins de tus addons)
	local function showable(mdl)
		return file.Exists(mdl, "GAME") and not (mdl:find("_anm", 1, true) or mdl:find("_animations", 1, true)
			or mdl:find("_gestures", 1, true) or mdl:find("_postures", 1, true))
	end
	local addFav -- definida abajo, después de refreshFavs
	local function populate()
		grid:Clear()
		local q = search:GetValue():lower()
		for mdl, name in SortedPairsByValue(list) do
			if (q == "" or name:lower():find(q, 1, true)) and showable(mdl) then
				local icon = grid:Add("SpawnIcon")
				icon:SetSize(72, 72) icon:SetModel(mdl) icon:SetTooltip(name)
				icon.DoClick = function() pick(mdl) end
				icon.DoRightClick = function()
					menu({
						{ T("select"), "icon16/user.png", function() pick(mdl) end },
						{ T("addFav"), "icon16/star.png", function() pick(mdl) addFav() end },
						false,
						{ T("copyPath"), "icon16/page_copy.png", function() SetClipboardText(mdl) end },
						{ T("rebuild"), "icon16/arrow_refresh.png", function() icon:RebuildSpawnIcon() end },
					})
				end
			end
		end
	end
	search.OnValueChange = populate
	populate()
	-- addons recién suscritos/activados sin reiniciar el mapa
	rescan.DoClick = function() list = allModels() populate() end

	local function refreshFavs()
		favGrid:Clear()
		for i, fav in ipairs(data.favs) do
			local icon = favGrid:Add("SpawnIcon")
			icon:SetSize(96, 96) icon:SetModel(fav.cfg.mdl, fav.cfg.skin or 0) icon:SetTooltip(fav.name)
			local over = icon.PaintOver
			icon.PaintOver = function(s, w, h)
				if over then over(s, w, h) end
				draw.SimpleTextOutlined(fav.name, "DermaDefaultBold", w / 2, h - 4, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
			end
			icon.DoClick = function() load(fav.cfg) end
			icon.DoRightClick = function()
				menu({
					{ T("load"), "icon16/user_go.png", function() load(fav.cfg) end },
					{ T("overwrite"), "icon16/disk.png", function()
						if sel.mdl then fav.cfg = current() saveData(data) refreshFavs() end
					end },
					{ T("rename"), "icon16/textfield_rename.png", function()
						Derma_StringRequest(T("rename"), T("namePrompt"), fav.name, function(name)
							if name ~= "" then fav.name = name saveData(data) refreshFavs() end
						end)
					end },
					false,
					{ T("delete"), "icon16/delete.png", function() table.remove(data.favs, i) saveData(data) refreshFavs() end },
				})
			end
		end
		noFavs:SetVisible(#data.favs == 0)
	end
	refreshFavs()
	-- guarda lo que está en el preview (modelo + skin + bodygroups + cara + colores)
	addFav = function()
		if not sel.mdl then return end
		local cfg = current()
		Derma_StringRequest(T("favorite"), T("namePrompt"), list[sel.mdl] or string.StripExtension(string.GetFileFromFilename(sel.mdl)), function(name)
			if name == "" then return end
			table.insert(data.favs, { name = name, cfg = cfg }) saveData(data) refreshFavs()
		end)
	end
	preview.DoRightClick = function()
		if not sel.mdl then return end
		menu({
			{ T("addFav"), "icon16/star.png", addFav },
			{ T("reset"), "icon16/arrow_refresh.png", function() pick(sel.mdl) end },
		})
	end

	button(bar, T("remove"), LEFT, function()
		data.last = nil saveData(data)
		choose({ wsid = "none" })
		f:Close()
	end)
	local langBtn = button(bar, lang():upper(), RIGHT, function()
		LANG:SetString(lang() == "en" and "es" or "en")
		f:Close()
		timer.Simple(0, function() RunConsoleCommand("skinshare") end)
	end)
	langBtn:SetWide(40)
	button(bar, T("reset"), LEFT, function() if sel.mdl then pick(sel.mdl) end end)
	local dice = button(bar, "", LEFT, function()
		local pool = {}
		for mdl in pairs(list) do if showable(mdl) then pool[#pool + 1] = mdl end end
		if #pool > 0 then pick(pool[math.random(#pool)]) end
	end)
	dice:SetWide(34) dice:SetImage("icon16/arrow_switch.png") dice:SetTooltip(T("random"))
	local applyBtn = button(bar, T("apply"), FILL, function()
		if not sel.mdl then return end
		data.last = current() saveData(data)
		share(data.last)
		f:Close()
	end)
	applyBtn:SetFont("DermaDefaultBold") applyBtn:SetTextColor(color_white)
	applyBtn.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and ACCENT_HI or ACCENT) end

	derma.RefreshSkins() -- los paneles creados sin padre cachearon el skin Default

	-- arranca con lo que traes puesto
	local bg, flex = {}, {}
	for i = 0, me:GetNumBodyGroups() - 1 do bg[i] = me:GetBodygroup(i) end
	for i = 0, me:GetFlexNum() - 1 do flex[i] = me:GetFlexWeight(i) end
	pick(me:GetModel(), me:GetSkin(), bg, flex)
end)

-- skinshare_fav "nombre": usa un favorito sin abrir el menú (sirve para binds)
concommand.Add("skinshare_fav", function(_, _, args)
	local data, name = loadData(), (args[1] or ""):lower()
	for _, fav in ipairs(data.favs) do
		if fav.name:lower() == name then data.last = fav.cfg saveData(data) share(fav.cfg) return end
	end
	print("[SkinShare] favorite not found: " .. name)
end, function(cmd)
	local out = {}
	for _, fav in ipairs(loadData().favs) do out[#out + 1] = cmd .. ' "' .. fav.name .. '"' end
	return out
end)

-- skinshare_random: un favorito al azar (para binds)
concommand.Add("skinshare_random", function()
	local data = loadData()
	local fav = table.Random(data.favs)
	if not fav then return warn(T("noFavsRandom")) end
	data.last = fav.cfg saveData(data) share(fav.cfg)
end)

-- ícono en el menú C de Sandbox
list.Set("DesktopWindows", "SkinShare", {
	title = "SkinShare", icon = "icon64/playermodel.png",
	init = function(_, window) window:Remove() RunConsoleCommand("skinshare") end,
})

