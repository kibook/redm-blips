local PlayerBlips = {}
local EntityBlips = {}
local LocationBlips = {}

local Peds = {}
local Vehicles = {}

local PlayerBlipSprite = Config.PlayerBlipSprite

function BlipAddForEntity(blip, entity)
	return Citizen.InvokeNative(0x23f74c2fda6e7c61, blip, entity)
end

function BlipAddForCoord(blipHash, x, y, z)
	return Citizen.InvokeNative(0x554D9D53F696D002, blipHash, x, y, z)
end

function GetPedCrouchMovement(ped)
	return Citizen.InvokeNative(0xD5FE956C70FF370B, ped)
end

function SetBlipNameFromPlayerString(blip, playerString)
	Citizen.InvokeNative(0x9CB1A1623062F402 , blip, playerString)
end

local entityEnumerator = {
	__gc = function(enum)
		if enum.destructor and enum.handle then
			enum.destructor(enum.handle)
		end
		enum.destructor = nil
		enum.handle = nil
	end
}

function EnumerateEntities(firstFunc, nextFunc, endFunc)
	return coroutine.wrap(function()
		local iter, id = firstFunc()

		if not id or id == 0 then
			endFunc(iter)
			return
		end

		local enum = {handle = iter, destructor = endFunc}
		setmetatable(enum, entityEnumerator)

		local next = true
		repeat
			coroutine.yield(id)
			next, id = nextFunc(iter)
		until not next

		enum.destructor, enum.handle = nil, nil
		endFunc(iter)
	end)
end

function EnumerateObjects()
	return EnumerateEntities(FindFirstObject, FindNextObject, EndFindObject)
end

function EnumeratePeds()
	return EnumerateEntities(FindFirstPed, FindNextPed, EndFindPed)
end

function EnumerateVehicles()
	return EnumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

function IsVisiblePlayer(ped)
	local myPed = PlayerPedId()
	return ped ~= myPed and IsPedAPlayer(ped) and not GetPedCrouchMovement(ped)
end

function IsInvisiblePlayer(ped)
	local myPed = PlayerPedId()
	return ped ~= myPed and IsPedAPlayer(ped) and GetPedCrouchMovement(ped)
end

function AddBlip(table, entity, blipHash)
	if not table[entity] or not DoesBlipExist(table[entity]) then
		local blip = BlipAddForEntity(blipHash, entity)
		table[entity] = blip
		return blip
	end
	return nil
end

function AddPlayerBlip(ped)
	local blip = AddBlip(PlayerBlips, ped, PlayerBlipSprite)
	SetBlipNameToPlayerName(blip, NetworkGetPlayerIndexFromPed(ped))
end

function AddTrainBlip(vehicle)
	local blip = AddBlip(EntityBlips, vehicle, Config.TrainBlipSprite)
	SetBlipNameFromPlayerString(blip, CreateVarString(10, "LITERAL_STRING", "Train"))
end

function IsTrain(entity)
	local model = GetEntityModel(entity)

	for _, train in ipairs(Config.Trains) do
		if model == GetHashKey(train) then
			return true
		end
	end

	return false
end

function AddBlipsForEntities()
	for _, ped in ipairs(Peds) do
		if IsVisiblePlayer(ped) then
			AddPlayerBlip(ped)
		end
	end

	for _, vehicle in ipairs(Vehicles) do
		if IsTrain(vehicle) then
			AddTrainBlip(vehicle)
		end
	end
end

function AddLocationBlip(location)
	local blip = BlipAddForCoord(1664425300, location.coords)
	SetBlipSprite(blip, location.sprite, true)

	if blip then
		SetBlipNameFromPlayerString(blip, CreateVarString(10, "LITERAL_STRING", location.name))
		LocationBlips[blip] = location
	end
end

function UpdateBlips()
	for entity, blip in pairs(PlayerBlips) do
		if not DoesEntityExist(entity) or not IsPedAPlayer(entity) or IsInvisiblePlayer(entity) then
			RemoveBlip(blip)
			PlayerBlips[entity] = nil
		end
	end

	for entity, blip in pairs(EntityBlips) do
		if not DoesEntityExist(entity) then
			RemoveBlip(blip)
			EntityBlips[entity] = nil
		end
	end

	for blip, location in pairs(LocationBlips) do
		if not DoesBlipExist(blip) then
			LocationBlips[blip] = nil
			AddLocationBlip(location)
		end
	end

	AddBlipsForEntities()
end

function RemoveAllPlayerBlips()
	for entity, blip in pairs(PlayerBlips) do
		RemoveBlip(blip)
	end
	PlayerBlips = {}
end

function RemoveAllEntityBlips()
	for entity, blip in pairs(EntityBlips) do
		RemoveBlip(blip)
	end
	EntityBlips = {}
end

function RemoveAllLocationBlips()
	for blip, location in pairs(LocationBlips) do
		RemoveBlip(blip)
	end
	LocationBlips = {}
end

function RemoveAllBlips()
	RemoveAllPlayerBlips()
	RemoveAllEntityBlips()
	RemoveAllLocationBlips()
end

function IsNearby(myPed, entity, distance)
	if not distance then
		return true
	end

	local myCoords = GetEntityCoords(myPed)
	local entityCoords = GetEntityCoords(entity)

	return #(myCoords.xy - entityCoords.xy) <= distance
end

function SetPlayerBlipSprite(sprite)
	if sprite then
		PlayerBlipSprite = sprite
	else
		PlayerBlipSprite = Config.PlayerBlipSprite
	end

	RemoveAllPlayerBlips()
end

exports("setPlayerBlipSprite", SetPlayerBlipSprite)

RegisterCommand("blips_debug", function(source, args, raw)
	print(json.encode(LocationBlips))
end, false)

AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() == resourceName then
		RemoveAllBlips()
	end
end)

Citizen.CreateThread(function()
	for _, location in ipairs(Config.Locations) do
		AddLocationBlip(location)
	end
end)

Citizen.CreateThread(function()
	while true do
		Peds = {}
		Vehicles = {}

		for ped in EnumeratePeds() do
			table.insert(Peds, ped)
		end

		for veh in EnumerateVehicles() do
			table.insert(Vehicles, veh)
		end

		Citizen.Wait(1000)
	end
end)

Citizen.CreateThread(function()
	while true do
		UpdateBlips()
		Citizen.Wait(500)
	end
end)
