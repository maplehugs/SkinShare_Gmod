-- SkinShare: un jugador elige uno de SUS addons de modelos y todos lo descargan y montan en partida.
AddCSLuaFile()
local VERSION = "0.7.1"
print("SkinShare v" .. VERSION)

local function mount(wsid, cb)
	if wsid == "0" then return cb({}) end -- modelo del juego base, todos lo tienen
	steamworks.DownloadUGC(wsid, function(path)
		if not path then return end
		local ok, files = game.MountGMA(path)
		if ok then cb(files) end
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
	local skins = {} -- [steamid64] = {wsid, mdl, arms, skin, bg, flex, col, wcol, waiting, ready}

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
			ply:ChatPrint("SkinShare: espera un segundo y vuelve a intentarlo.")
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

local function slider(parent, label, min, max, decimals, val, onChange)
	local s = parent:Add("DNumSlider")
	s:Dock(TOP) s:SetText(label) s:SetDark(true) s:SetDecimals(decimals) s:SetMinMax(min, max) s:SetValue(val)
	s.OnValueChanged = function(_, v) onChange(decimals == 0 and math.Round(v) or v) end
end

local function button(parent, text, dock, onClick)
	local b = parent:Add("DButton")
	b:Dock(dock) b:SetText(text) b.DoClick = onClick
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

	local right = f:Add("DPanel")
	right:Dock(RIGHT) right:SetWide(f:GetWide() * 0.45)
	local bar = right:Add("DPanel")
	bar:Dock(BOTTOM) bar:SetTall(32) bar:SetPaintBackground(false)
	local sheet = right:Add("DPropertySheet")
	sheet:Dock(FILL)

	-- Modelos
	local models = vgui.Create("DPanel")
	local search = models:Add("DTextEntry")
	search:Dock(TOP) search:SetPlaceholderText("Buscar...") search:SetUpdateOnType(true)
	local scroll = models:Add("DScrollPanel")
	scroll:Dock(FILL)
	local grid = scroll:Add("DIconLayout")
	grid:Dock(TOP) grid:SetSpaceX(4) grid:SetSpaceY(4)
	sheet:AddSheet("Modelos", models, "icon16/user.png")

	-- Favoritos
	local favs = vgui.Create("DPanel")
	local favBar = favs:Add("DPanel")
	favBar:Dock(BOTTOM) favBar:SetTall(28) favBar:SetPaintBackground(false)
	local favList = favs:Add("DListView")
	favList:Dock(FILL) favList:SetMultiSelect(false) favList:AddColumn("Nombre")
	sheet:AddSheet("Favoritos", favs, "icon16/star.png")

	-- Bodygroups, skin y caras
	local bgPanel = vgui.Create("DScrollPanel")
	bgPanel:DockPadding(8, 8, 8, 8)
	local bgTab = sheet:AddSheet("Bodygroups", bgPanel, "icon16/group.png").Tab
	local flexPanel = vgui.Create("DScrollPanel")
	flexPanel:DockPadding(8, 8, 8, 8)
	local flexTab = sheet:AddSheet("Cara", flexPanel, "icon16/emoticon_wink.png").Tab

	-- Colores
	local colors = vgui.Create("DPanel")
	local function mixer(label, vec)
		local l = colors:Add("DLabel")
		l:Dock(TOP) l:DockMargin(8, 8, 8, 0) l:SetText(label) l:SetDark(true)
		local m = colors:Add("DColorMixer")
		m:Dock(TOP) m:DockMargin(8, 4, 8, 0) m:SetTall(180) m:SetAlphaBar(false) m:SetPalette(false) m:SetVector(vec)
		return m
	end
	local pcol = mixer("Color del jugador", me:GetPlayerColor())
	local wcol = mixer("Color del arma (physgun, etc.)", me:GetWeaponColor())
	sheet:AddSheet("Colores", colors, "icon16/color_wheel.png")

	-- preview: arrastra para girar, rueda para zoom
	local preview = f:Add("DModelPanel")
	preview:Dock(FILL) preview:SetFOV(36) preview:SetAnimated(true)
	preview:SetCamPos(Vector(0, 0, 0)) preview:SetLookAt(Vector(-100, 0, -22))
	local yaw, zoom = 0, 0
	function preview:DragMousePress() self.px = gui.MouseX() end
	function preview:DragMouseRelease() self.px = nil end
	function preview:OnMouseWheeled(d) zoom = math.Clamp(zoom + d * 8, -80, 60) end
	function preview:LayoutEntity(ent)
		self:RunAnimation()
		if self.px then yaw = yaw + gui.MouseX() - self.px self.px = gui.MouseX() end
		ent:SetAngles(Angle(0, yaw, 0))
		ent:SetPos(Vector(-100 + zoom, 0, -61))
	end

	local sel = {}
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

	local list = allModels()
	local function populate()
		grid:Clear()
		local q = search:GetValue():lower()
		for mdl, name in SortedPairsByValue(list) do
			if q == "" or name:lower():find(q, 1, true) then
				local icon = grid:Add("SpawnIcon")
				icon:SetSize(64, 64) icon:SetModel(mdl) icon:SetTooltip(name)
				icon.DoClick = function() pick(mdl) end
			end
		end
	end
	search.OnValueChange = populate
	populate()

	local function refreshFavs()
		favList:Clear()
		for i, fav in ipairs(data.favs) do favList:AddLine(fav.name).fav = i end
	end
	refreshFavs()
	local function selectedFav()
		local _, line = favList:GetSelectedLine()
		return line and line.fav
	end
	favList.DoDoubleClick = function(_, _, line) load(data.favs[line.fav].cfg) end
	button(favBar, "Borrar", RIGHT, function()
		local i = selectedFav()
		if i then table.remove(data.favs, i) saveData(data) refreshFavs() end
	end)
	button(favBar, "Cargar", RIGHT, function()
		local i = selectedFav()
		if i then load(data.favs[i].cfg) end
	end)
	button(favBar, "Guardar actual", FILL, function()
		if not sel.mdl then return end
		Derma_StringRequest("Favorito", "Nombre:", string.StripExtension(string.GetFileFromFilename(sel.mdl)), function(name)
			if name == "" then return end
			table.insert(data.favs, { name = name, cfg = current() }) saveData(data) refreshFavs()
		end)
	end)

	button(bar, "Quitar skin", LEFT, function()
		data.last = nil saveData(data)
		choose({ wsid = "none" })
		f:Close()
	end)
	button(bar, "Reiniciar", LEFT, function() if sel.mdl then pick(sel.mdl) end end)
	button(bar, "Usar y compartir", FILL, function()
		if not sel.mdl then return end
		data.last = current() saveData(data)
		choose(data.last)
		f:Close()
	end)

	-- arranca con lo que traes puesto
	local bg, flex = {}, {}
	for i = 0, me:GetNumBodyGroups() - 1 do bg[i] = me:GetBodygroup(i) end
	for i = 0, me:GetFlexNum() - 1 do flex[i] = me:GetFlexWeight(i) end
	pick(me:GetModel(), me:GetSkin(), bg, flex)
end)

hook.Add("OnPlayerChat", "skinshare", function(ply, text)
	if ply == LocalPlayer() and text:lower() == "!skin" then RunConsoleCommand("skinshare") return true end
end)
