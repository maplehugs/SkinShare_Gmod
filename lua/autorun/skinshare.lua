-- SkinShare: un jugador elige uno de SUS addons de modelos y todos lo descargan y montan en partida.
AddCSLuaFile()
local VERSION = "0.11.0"
print("SkinShare v" .. VERSION)

local MAX_SIZE = 300 * 1024 * 1024

local function download(wsid, cb)
	steamworks.DownloadUGC(wsid, function(path)
		if not path then return end
		local ok, files = game.MountGMA(path)
		if ok then cb(files) end
	end)
end

-- nil si se puede compartir; si no, el motivo (clave de STRINGS)
local function rejected(info)
	if not info then return "whyMissing" end
	if not tostring(info.tags or ""):lower():find("model", 1, true) then return "whyTag" end
	if (tonumber(info.size) or 0) > MAX_SIZE then return "whySize" end
end

local function mount(wsid, cb)
	if wsid == "0" then return cb({}) end -- modelo del juego base, todos lo tienen
	if not steamworks.FileInfo then return download(wsid, cb) end
	-- cualquiera puede pedir una skin: solo se montan items con tag Model y de tamaño razonable,
	-- para que nadie obligue a todos a montar un pack que reemplace texturas o sonidos
	steamworks.FileInfo(wsid, function(info)
		if not rejected(info) then download(wsid, cb) end
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
		-- las manos que registra el addon del cliente no existen aquí (su Lua no corre): se usan las *_arms.mdl que mandó
		local hands = ply:GetHands()
		if s.arms ~= "" and IsValid(hands) and file.Exists(s.arms, "GAME") then
			hands:SetModel(s.arms) hands:SetSkin(0) hands:SetBodyGroups("0000000")
		end
		return true
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

		if (ply.skinshareNext or 0) > CurTime() then
			ply:ChatPrint("SkinShare: too fast, wait a second and try again.")
			return
		end
		ply.skinshareNext = CurTime() + 1

		if wsid == "none" then -- volver a la skin y colores del gamemode
			skins[ply:SteamID64()] = nil
			-- cl_playercolor solo existe en Sandbox; antes del gamemode para que TTT ponga los suyos
			local pc, wc = ply:GetInfo("cl_playercolor"), ply:GetInfo("cl_weaponcolor")
			if pc ~= "" then ply:SetPlayerColor(Vector(pc)) end
			if wc ~= "" then ply:SetWeaponColor(Vector(wc)) end
			if ply:Alive() and GAMEMODE.PlayerSetModel then GAMEMODE:PlayerSetModel(ply) end
			if ply.SetupHands then ply:SetupHands() end
			return
		end

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

net.Receive("skinshare", function()
	local ply, wsid, mdl = net.ReadEntity(), net.ReadString(), net.ReadString()
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
	for _, v in pairs(player_manager.AllValidModels()) do
		if v:lower() == mdl then return "" end -- registrado: SetupHands ya pone las manos correctas
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
		whyTag = "the addon isn't tagged \"Model\" on the Workshop.", whySize = "the addon is bigger than 300 MB." },
	es = { search = "Buscar...", models = "Modelos", favorites = "Favoritos", bodygroups = "Bodygroups",
		face = "Cara", colors = "Colores", playercolor = "Color del jugador", weaponcolor = "Color del arma (physgun, etc.)",
		delete = "Borrar", load = "Cargar", favorite = "Favorito", namePrompt = "Nombre:", rename = "Renombrar",
		addFav = "Agregar a favoritos", select = "Seleccionar", rebuild = "Regenerar ícono", overwrite = "Sobrescribir con el actual", noFavs = "Clic derecho en un modelo para agregarlo aquí.",
		hint = "Arrastra: girar   Rueda: zoom   Clic derecho: favorito",
		remove = "Quitar skin", reset = "Reiniciar", apply = "Usar y compartir",
		cantShare = "Los demás no pueden descargar esta skin: ", whyMissing = "el addon es privado, está oculto o no existe.",
		whyTag = "el addon no tiene el tag \"Model\" en el Workshop.", whySize = "el addon pesa más de 300 MB." },
}
local function lang()
	local l = LANG:GetString()
	if l == "auto" then l = GetConVar("gmod_language"):GetString():sub(1, 2) end
	return STRINGS[l] and l or "en"
end
local function T(key) return STRINGS[lang()][key] end

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
	local search = models:Add("DTextEntry")
	search:Dock(TOP) search:DockMargin(0, 0, 0, 6) search:SetTall(26) search:SetPlaceholderText(T("search")) search:SetUpdateOnType(true)
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
						{ T("rebuild"), "icon16/arrow_refresh.png", function() icon:RebuildSpawnIcon() end },
					})
				end
			end
		end
	end
	search.OnValueChange = populate
	populate()

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
	local applyBtn = button(bar, T("apply"), FILL, function()
		if not sel.mdl then return end
		data.last = current() saveData(data)
		choose(data.last)
		f:Close()
		if data.last.wsid ~= "0" and steamworks.FileInfo then
			steamworks.FileInfo(data.last.wsid, function(info)
				local why = rejected(info)
				if why then chat.AddText(Color(255, 90, 90), "[SkinShare] ", color_white, T("cantShare") .. T(why)) end
			end)
		end
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
		if fav.name:lower() == name then data.last = fav.cfg saveData(data) choose(fav.cfg) return end
	end
	print("[SkinShare] favorite not found: " .. name)
end, function(cmd)
	local out = {}
	for _, fav in ipairs(loadData().favs) do out[#out + 1] = cmd .. ' "' .. fav.name .. '"' end
	return out
end)

-- ícono en el menú C de Sandbox
list.Set("DesktopWindows", "SkinShare", {
	title = "SkinShare", icon = "icon64/playermodel.png",
	init = function(_, window) window:Remove() RunConsoleCommand("skinshare") end,
})

