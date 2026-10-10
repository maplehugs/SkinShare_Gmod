-- SkinShare: un jugador elige uno de SUS addons de modelos y todos lo descargan y montan en partida.
AddCSLuaFile()

local function mount(wsid, cb)
	if wsid == "0" then return cb({}) end -- modelo del juego base, todos lo tienen
	steamworks.DownloadUGC(wsid, function(path)
		if not path then return end
		local ok, files = game.MountGMA(path)
		if ok then cb(files) end
	end)
end

if SERVER then
	util.AddNetworkString("skinshare")
	local skins = {} -- [steamid64] = {wsid, mdl, skin, bg, col}

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

	-- forzar: cualquier SetModel del gamemode (TTT, etc.) se cambia por la skin elegida
	local meta = FindMetaTable("Player")
	meta.SkinShareRawSetModel = meta.SkinShareRawSetModel or meta.SetModel
	function meta:SetModel(m)
		local s = skins[self:SteamID64()]
		if not (s and isstring(m) and (m == s.mdl or isPlayerModel(m)) and file.Exists(s.mdl, "GAME")) then
			return self:SkinShareRawSetModel(m)
		end
		self:SkinShareRawSetModel(s.mdl)
		self:SetSkin(math.min(s.skin, self:SkinCount() - 1))
		local i = 0
		for v in s.bg:gmatch("%d+") do self:SetBodygroup(i, tonumber(v)) i = i + 1 end
	end

	local function apply(ply)
		local s = skins[ply:SteamID64()]
		if not (s and file.Exists(s.mdl, "GAME")) then return end
		ply:SetModel(s.mdl)
		ply:SetPlayerColor(s.col)
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

		if (ply.skinshareNext or 0) > CurTime() then return end
		ply.skinshareNext = CurTime() + 5
		local mdl, skin, bg, col = net.ReadString(), net.ReadUInt(8), net.ReadString(), net.ReadVector()
		if not wsid:match("^%d+$") or not mdl:match("^models/[%w_%-%./]+%.mdl$") or mdl:find("..", 1, true) then return end
		if #bg > 255 or not bg:match("^[%d ]*$") then return end
		col = Vector(math.Clamp(col.x, 0, 1), math.Clamp(col.y, 0, 1), math.Clamp(col.z, 0, 1))

		local s = { wsid = wsid, mdl = mdl, skin = skin, bg = bg, col = col }
		skins[ply:SteamID64()] = s
		send(ply, s)
		-- listen server: el cliente del host monta el GMA y comparte filesystem con el server
		if game.IsDedicated() and steamworks.DownloadUGC then mount(wsid, function() end) end

		local name = "skinshare_" .. ply:SteamID64()
		timer.Create(name, 1, 60, function()
			if not IsValid(ply) or apply(ply) then timer.Remove(name) end
		end)
	end)

	-- después del gamemode (TTT/Sandbox ponen su modelo en PlayerSpawn)
	hook.Add("PlayerSpawn", "skinshare", function(ply)
		timer.Simple(0, function() if IsValid(ply) then apply(ply) end end)
	end)

	hook.Add("PlayerDisconnected", "skinshare", function(ply) skins[ply:SteamID64()] = nil end)
	return
end

local function choose(wsid, mdl, skin, bg, col)
	net.Start("skinshare") net.WriteString(wsid)
	if wsid ~= "" then
		net.WriteString(mdl) net.WriteUInt(skin, 8) net.WriteString(bg) net.WriteVector(col)
	end
	net.SendToServer()
end

net.Receive("skinshare", function()
	local ply, wsid, mdl = net.ReadEntity(), net.ReadString(), net.ReadString()
	mount(wsid, function()
		-- ponytail: refresco local del modelo; si el jugador no estaba visible se ve al respawnear
		if IsValid(ply) then ply:SetModel(mdl) end
	end)
end)

hook.Add("InitPostEntity", "skinshare", function() choose("") end)

-- mismo truco que duplicator.FigureOutRequiredAddons
local function addonFor(mdl)
	for _, a in ipairs(engine.GetAddons()) do
		if a.mounted and file.Exists(mdl, a.title) then return tostring(a.wsid) end
	end
	return "0"
end

local function slider(parent, label, max, val, onChange)
	local s = parent:Add("DNumSlider")
	s:Dock(TOP) s:SetText(label) s:SetDark(true) s:SetDecimals(0) s:SetMinMax(0, max) s:SetValue(val)
	s.OnValueChanged = function(_, v) onChange(math.Round(v)) end
end

-- interfaz al estilo Enhanced PlayerModel Selector: preview a la izquierda, pestañas a la derecha
concommand.Add("skinshare", function()
	local me = LocalPlayer()
	local f = vgui.Create("DFrame")
	f:SetSize(math.min(ScrW() - 16, 960), math.min(ScrH() - 16, 700)) f:Center()
	f:SetTitle("SkinShare") f:MakePopup()

	local right = f:Add("DPanel")
	right:Dock(RIGHT) right:SetWide(f:GetWide() * 0.45)
	local btn = right:Add("DButton")
	btn:Dock(BOTTOM) btn:SetTall(32) btn:SetText("Usar y compartir")
	local sheet = right:Add("DPropertySheet")
	sheet:Dock(FILL)

	-- Modelos
	local models = vgui.Create("DPanel")
	local search = models:Add("DTextEntry")
	search:Dock(TOP) search:SetPlaceholderText("Buscar...") search:SetUpdateOnType(true)
	local scroll = models:Add("DScrollPanel")
	scroll:Dock(FILL)
	local grid = scroll:Add("DIconLayout")
	grid:Dock(FILL) grid:SetSpaceX(4) grid:SetSpaceY(4)
	sheet:AddSheet("Modelos", models, "icon16/user.png")

	-- Bodygroups y skin
	local bgPanel = vgui.Create("DScrollPanel")
	bgPanel:DockPadding(8, 8, 8, 8)
	local bgTab = sheet:AddSheet("Bodygroups", bgPanel, "icon16/group.png").Tab

	-- Color
	local mixer = vgui.Create("DColorMixer")
	mixer:SetAlphaBar(false) mixer:SetPalette(false) mixer:SetVector(me:GetPlayerColor())
	sheet:AddSheet("Color", mixer, "icon16/color_wheel.png")

	local preview = f:Add("DModelPanel") -- su LayoutEntity por defecto ya lo hace girar
	preview:Dock(FILL) preview:SetFOV(36) preview:SetAnimated(true)
	preview:SetCamPos(Vector(0, 0, 0)) preview:SetLookAt(Vector(-100, 0, -22))

	local sel = {}
	local function pick(mdl, skin, bgs)
		sel = { mdl = mdl, skin = skin or 0, bg = bgs or {} }
		preview:SetModel(mdl)
		local ent = preview.Entity
		ent:SetPos(Vector(-100, 0, -61))
		ent.GetPlayerColor = function() return mixer:GetVector() end
		local seq = ent:LookupSequence("idle_all_01")
		if seq > 0 then ent:ResetSequence(seq) end

		bgPanel:Clear()
		ent:SetSkin(sel.skin)
		if ent:SkinCount() > 1 then
			slider(bgPanel, "Skin", ent:SkinCount() - 1, sel.skin, function(v) sel.skin = v ent:SetSkin(v) end)
		end
		for i = 0, ent:GetNumBodyGroups() - 1 do
			sel.bg[i] = sel.bg[i] or 0
			ent:SetBodygroup(i, sel.bg[i])
			if ent:GetBodygroupCount(i) > 1 then
				slider(bgPanel, ent:GetBodygroupName(i), ent:GetBodygroupCount(i) - 1, sel.bg[i], function(v) sel.bg[i] = v ent:SetBodygroup(i, v) end)
			end
		end
		bgTab:SetVisible(#bgPanel:GetCanvas():GetChildren() > 0)
		sheet.tabScroller:InvalidateLayout(true)
	end

	local function populate()
		grid:Clear()
		local q = search:GetValue():lower()
		for name, mdl in SortedPairs(player_manager.AllValidModels()) do
			if q == "" or name:lower():find(q, 1, true) then
				local icon = grid:Add("SpawnIcon")
				icon:SetSize(64, 64) icon:SetModel(mdl) icon:SetTooltip(name)
				icon.DoClick = function() pick(mdl) end
			end
		end
	end
	search.OnValueChange = populate
	populate()

	local cur = {}
	for i = 0, me:GetNumBodyGroups() - 1 do cur[i] = me:GetBodygroup(i) end
	pick(me:GetModel(), me:GetSkin(), cur)

	btn.DoClick = function()
		local bg = {}
		for i = 0, preview.Entity:GetNumBodyGroups() - 1 do bg[#bg + 1] = sel.bg[i] or 0 end
		choose(addonFor(sel.mdl), sel.mdl, sel.skin, table.concat(bg, " "), mixer:GetVector())
		f:Close()
	end
end)

hook.Add("OnPlayerChat", "skinshare", function(ply, text)
	if ply == LocalPlayer() and text:lower() == "!skin" then RunConsoleCommand("skinshare") return true end
end)
