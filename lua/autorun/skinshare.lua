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
	local skins = {} -- [steamid64] = {wsid, mdl}

	local function send(ply, s, to)
		net.Start("skinshare")
		net.WriteEntity(ply) net.WriteString(s.wsid) net.WriteString(s.mdl)
		if to then net.Send(to) else net.Broadcast() end
	end

	local function apply(ply)
		local s = skins[ply:SteamID64()]
		if s and file.Exists(s.mdl, "GAME") then ply:SetModel(s.mdl) return true end
	end

	net.Receive("skinshare", function(_, ply)
		local wsid, mdl = net.ReadString(), net.ReadString()

		if wsid == "" then -- recién conectado: mándale las skins actuales
			for _, p in ipairs(player.GetAll()) do
				local s = skins[p:SteamID64()]
				if s then send(p, s, ply) end
			end
			return
		end

		if (ply.skinshareNext or 0) > CurTime() then return end
		ply.skinshareNext = CurTime() + 5
		if not wsid:match("^%d+$") or not mdl:match("^models/[%w_%-%./]+%.mdl$") or mdl:find("..", 1, true) then return end

		local s = { wsid = wsid, mdl = mdl }
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

local function choose(wsid, mdl)
	net.Start("skinshare") net.WriteString(wsid) net.WriteString(mdl) net.SendToServer()
end

net.Receive("skinshare", function()
	local ply, wsid, mdl = net.ReadEntity(), net.ReadString(), net.ReadString()
	mount(wsid, function()
		-- ponytail: refresco local del modelo; si el jugador no estaba visible se ve al respawnear
		if IsValid(ply) then ply:SetModel(mdl) end
	end)
end)

hook.Add("InitPostEntity", "skinshare", function() choose("", "") end)

-- mismo truco que duplicator.FigureOutRequiredAddons
local function addonFor(mdl)
	for _, a in ipairs(engine.GetAddons()) do
		if a.mounted and file.Exists(mdl, a.title) then return tostring(a.wsid) end
	end
	return "0"
end

-- interfaz al estilo Enhanced PlayerModel Selector: preview a la izquierda, iconos a la derecha
concommand.Add("skinshare", function()
	local f = vgui.Create("DFrame")
	f:SetSize(math.min(ScrW() - 16, 960), math.min(ScrH() - 16, 700)) f:Center()
	f:SetTitle("SkinShare") f:MakePopup()

	local right = f:Add("DPanel")
	right:Dock(RIGHT) right:SetWide(f:GetWide() * 0.45)
	local search = right:Add("DTextEntry")
	search:Dock(TOP) search:SetPlaceholderText("Buscar...") search:SetUpdateOnType(true)
	local btn = right:Add("DButton")
	btn:Dock(BOTTOM) btn:SetTall(32) btn:SetText("Usar y compartir") btn:SetEnabled(false)
	local scroll = right:Add("DScrollPanel")
	scroll:Dock(FILL)
	local grid = scroll:Add("DIconLayout")
	grid:Dock(FILL) grid:SetSpaceX(4) grid:SetSpaceY(4)

	local preview = f:Add("DModelPanel") -- su LayoutEntity por defecto ya lo hace girar
	preview:Dock(FILL) preview:SetFOV(36) preview:SetAnimated(true)
	preview:SetCamPos(Vector(0, 0, 0)) preview:SetLookAt(Vector(-100, 0, -22))

	local selected
	local function pick(mdl)
		selected = mdl
		preview:SetModel(mdl)
		local ent = preview.Entity
		ent:SetPos(Vector(-100, 0, -61))
		ent.GetPlayerColor = function() return LocalPlayer():GetPlayerColor() end
		local seq = ent:LookupSequence("idle_all_01")
		if seq > 0 then ent:ResetSequence(seq) end
		btn:SetEnabled(true)
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
	pick(LocalPlayer():GetModel())

	btn.DoClick = function()
		choose(addonFor(selected), selected)
		f:Close()
	end
end)

hook.Add("OnPlayerChat", "skinshare", function(ply, text)
	if ply == LocalPlayer() and text:lower() == "!skin" then RunConsoleCommand("skinshare") return true end
end)
