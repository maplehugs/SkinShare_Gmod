-- SkinShare: un jugador elige uno de SUS addons de modelos y todos lo descargan y montan en partida.
AddCSLuaFile()

local function mount(wsid, cb)
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

concommand.Add("skinshare", function()
	local f = vgui.Create("DFrame")
	f:SetSize(480, 420) f:Center() f:SetTitle("SkinShare: elige uno de tus addons de modelos") f:MakePopup()

	local list = vgui.Create("DListView", f)
	list:Dock(FILL) list:SetMultiSelect(false) list:AddColumn("Addon")
	for _, a in ipairs(engine.GetAddons()) do
		if a.mounted and (a.models or 0) > 0 then list:AddLine(a.title).wsid = tostring(a.wsid) end
	end

	list.OnRowSelected = function(_, _, line)
		mount(line.wsid, function(files)
			local menu = DermaMenu()
			for _, p in ipairs(files) do
				if p:match("^models/.+%.mdl$") and not p:find("arms") and not p:find("hands") then
					menu:AddOption(p, function() choose(line.wsid, p) f:Close() end)
				end
			end
			menu:Open()
		end)
	end
end)

hook.Add("OnPlayerChat", "skinshare", function(ply, text)
	if ply == LocalPlayer() and text:lower() == "!skin" then RunConsoleCommand("skinshare") return true end
end)
