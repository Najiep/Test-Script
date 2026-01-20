local sharedConfig = require 'config.shared'

-- ESX Legacy + ox_inventory/ox_lib adaptation layer
local ESX = exports['es_extended']:getSharedObject()

-- If you use an external duty script, set this convar to true and update getOnDuty() below.
local USE_EXTERNAL_DUTY = GetConvarInt('qbx_police:useExternalDuty', 0) == 1

-- Runtime state (not persisted)
local dutyState = {}          -- [src] = true/false
local handcuffState = {}      -- [src] = true/false
local fingerprintState = {}   -- [src] = string
local jailedPlayers = {}      -- [src] = {name = ..., jailTime = ...}

local GSRData = {}
local GSR_DECAY_TIME = 15 * 60 -- 15 minutes

local function playerHasGsr(src)
    local data = GSRData[src]
    if not data then return false end

    local elapsed = os.time() - data.time

    if elapsed >= GSR_DECAY_TIME then
        GSRData[src] = nil
        return false
    end

    return true
end

local function applyGloveModifier(src)
    -- placeholder logic (palitan mo ng gloves check mo)
    local wearingGloves = false

    if wearingGloves then
        return math.random(1, 100) <= 60 -- 40% false negative
    end

    return true
end


RegisterNetEvent('qbx_police:server:addGSR', function(weapon)
    local src = source

    -- Ignore non-firearms
    if weapon == `WEAPON_STUNGUN` then return end

    GSRData[src] = {
        time = os.time(),
        strength = 100
    }
end)


local function notify(src, description, nType, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title or 'Police',
        description = description or '',
        type = nType or 'inform',
        duration = 5000
    })
end

local function getXPlayer(src)
    if not src then return nil end
    return ESX.GetPlayerFromId(src)
end

local function getIdentifier(xPlayer)
    return xPlayer and xPlayer.identifier or nil
end

local function getFullName(xPlayer)
    if not xPlayer then return 'Unknown' end
    local ok, name = pcall(function()
        return xPlayer.getName()
    end)
    if ok and name and name ~= '' then return name end
    return ('ID %s'):format(xPlayer.source or 'Unknown')
end

local function getJob(xPlayer)
    if not xPlayer then return nil end
    local ok, job = pcall(function()
        return xPlayer.getJob()
    end)
    return ok and job or nil
end

local function isLeoJob(jobName)
    return jobName == 'police' or jobName == 'sheriff' or jobName == 'state' or jobName == 'fib'
end

local function isEmsJob(jobName)
    return jobName == 'ambulance' or jobName == 'ems'
end

local function getOnDuty(src, jobName)
    -- Default: ESX has no built-in duty, so we treat players as on-duty.
    -- If you have a duty resource, set USE_EXTERNAL_DUTY=1 and implement your lookup here.
    if USE_EXTERNAL_DUTY then
        local state = Player(src) and Player(src).state
        if state and state.onDuty ~= nil then
            return state.onDuty == true
        end
        return dutyState[src] == true
    end
    return true
end

local function ensureFingerprints(src)
    if fingerprintState[src] then return fingerprintState[src] end
    local xPlayer = getXPlayer(src)
    local identifier = getIdentifier(xPlayer)
    if not identifier then
        fingerprintState[src] = ('%05d'):format(src)
        return fingerprintState[src]
    end

    local hash = GetHashKey(identifier)
    fingerprintState[src] = ('%08x'):format(hash)
    return fingerprintState[src]
end

local function getVehiclePlate(veh)
    if not veh or veh == 0 then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    return tostring(plate):gsub('^%s+', ''):gsub('%s+$', '')
end

local function spawnVehicleServer(model, coords, warpPed)
    local modelHash = type(model) == 'number' and model or joaat(model)
    if not modelHash or modelHash == 0 then return 0, 0 end

    if not IsModelInCdimage(modelHash) then return 0, 0 end
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(0)
    end

    local x, y, z, h
    if type(coords) == 'vector4' then
        x, y, z, h = coords.x, coords.y, coords.z, coords.w
    elseif type(coords) == 'vector3' then
        x, y, z, h = coords.x, coords.y, coords.z, 0.0
    elseif type(coords) == 'table' then
        x = coords.x or coords[1]
        y = coords.y or coords[2]
        z = coords.z or coords[3]
        h = coords.w or coords.h or coords[4] or 0.0
    end
    if not x or not y or not z then return 0, 0 end

    local veh = CreateVehicle(modelHash, x + 0.0, y + 0.0, z + 0.0, h + 0.0, true, true)
    if not veh or veh == 0 then return 0, 0 end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)

    if warpPed and warpPed ~= 0 then
        TaskWarpPedIntoVehicle(warpPed, veh, -1)
    end

    SetModelAsNoLongerNeeded(modelHash)
    return netId, veh
end

-- Minimal qb-style globals retained by this resource
Plates = {}
local playerStatus = {}
local casings = {}
local bloodDrops = {}
local fingerDrops = {}
local updatingCops = false

---@param src integer
---@param minGrade? integer
---@return boolean
local function isLeoAndOnDuty(src, minGrade)
    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if not job or not isLeoJob(job.name) then return false end
    if not getOnDuty(src, job.name) then return false end
    return (job.grade or 0) >= (minGrade or 0)
end

-- Functions
local function updateBlips()
    local dutyPlayers = {}
    local players = ESX.GetPlayers()
    for i = 1, #players do
        local src = players[i]
        local xPlayer = getXPlayer(src)
        local job = getJob(xPlayer)
        if job and (isLeoJob(job.name) or isEmsJob(job.name)) and getOnDuty(src, job.name) then
            local ped = GetPlayerPed(src)
            local coords = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)
            dutyPlayers[#dutyPlayers+1] = {
                job = job.name,
                source = src,
                label = getFullName(xPlayer),
                location = vec4(coords.x, coords.y, coords.z, heading)
            }
        end
    end

    TriggerClientEvent('police:client:UpdateBlips', -1, dutyPlayers)
end

local function generateId(table)
    local id = lib.string.random('11111')
    if not table then return id end
    while table[id] do
        id = lib.string.random('11111')
    end
    return id
end

local function oxHasExport(exportName)
    local ok, exists = pcall(function()
        return exports.ox_inventory and exports.ox_inventory[exportName] ~= nil
    end)
    return ok and exists
end

local function getItemCount(src, itemName)
    if oxHasExport('Search') then
        local count = exports.ox_inventory:Search(src, 'count', itemName)
        return tonumber(count) or 0
    end
    local xPlayer = getXPlayer(src)
    if not xPlayer then return 0 end
    local invItem = xPlayer.getInventoryItem(itemName)
    return (invItem and invItem.count) or 0
end

ESX.RegisterUsableItem('handcuffs', function(src)
    if not src then return end
    if getItemCount(src, 'handcuffs') < 1 then return end
    TriggerClientEvent('police:client:CuffPlayerSoft', src)
end)

ESX.RegisterUsableItem('moneybag', function(src)
    if not src then return end

    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if job and isLeoJob(job.name) then return end

    -- Preferred: read metadata via ox_inventory (ESX inventory doesn't carry metadata by default)
    if oxHasExport('GetSlotIdWithItem') and oxHasExport('GetSlot') and oxHasExport('RemoveItem') then
        local slot = exports.ox_inventory:GetSlotIdWithItem(src, 'moneybag')
        if not slot then return end
        local item = exports.ox_inventory:GetSlot(src, slot)
        local metadata = item and item.metadata or {}
        local cash = tonumber(metadata.cash)
        if not cash or cash <= 0 then return end

        if not exports.ox_inventory:RemoveItem(src, 'moneybag', 1, nil, slot) then return end
        if xPlayer then xPlayer.addMoney(cash) end
        return
    end

    -- Fallback: if no metadata support, just consume 1 moneybag and give a fixed amount.
    -- (Change/remove this fallback if your server never uses moneybags.)
    if getItemCount(src, 'moneybag') < 1 then return end
    if xPlayer then
        xPlayer.removeInventoryItem('moneybag', 1)
        xPlayer.addMoney(0)
    end
end)

-- Callbacks
lib.callback.register('police:server:isPlayerDead', function(_, playerId)
    local state = Player(playerId) and Player(playerId).state
    if not state then return false end
    return state.dead == true or state.isDead == true
end)

-- NEW: Check if player has tracker (ankle monitor)


lib.callback.register('police:GetPlayerStatus', function(_, targetSrc)
    if not getXPlayer(targetSrc) or not next(playerStatus[targetSrc] or {}) then return {} end
    local status = playerStatus[targetSrc]

    local statList = {}
    for i = 1, #status do
        statList[#statList + 1] = status[i].text
    end

    return statList
end)

lib.callback.register('police:GetImpoundedVehicles', function()
    return FetchImpoundedVehicles()
end)

lib.callback.register('qbx_police:server:spawnVehicle', function(source, model, coords, plate, giveKeys, vehId)
    local netId, veh = spawnVehicleServer(model, coords, GetPlayerPed(source))

    if not netId or netId == 0 or not veh or veh == 0 then return end

    SetVehicleNumberPlateText(veh, plate)

    -- Keys are framework-specific in ESX. Hook your keys resource here if needed.
    -- if giveKeys == true and GetResourceState('your_keys_resource') == 'started' then ... end

    if vehId then Entity(veh).state.vehicleid = vehId end
    return netId
end)

local function isPlateFlagged(plate)
    return Plates and Plates[plate] and Plates[plate].isflagged
end


lib.callback.register('qbx_police:server:isPlateFlagged', function(_, plate)
    return isPlateFlagged(plate)
end)

local function isPoliceForcePresent()
    local players = ESX.GetPlayers()
    for i = 1, #players do
        if isLeoAndOnDuty(players[i], 2) then
            return true
        end
    end
end

lib.callback.register('qbx_police:server:isPoliceForcePresent', isPoliceForcePresent)

--[[
    NEW FEATURE (Requested): F5 Police Interaction Menu
    Server-side validation + data fetch callbacks.
    - Access rules: job must be "police" and on duty (per spec)
    - Distance validated server-side
    - No changes to existing events/commands; only additive callbacks/events
]]

local function isPoliceOnDutyBySpec(src)
    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    return xPlayer and job and job.name == 'police' and getOnDuty(src, job.name) == true
end

local function isTargetTooFarStrict(src, targetSrc, maxDistance)
    maxDistance = maxDistance or 2.0
    local playerPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if playerPed == 0 or targetPed == 0 then return true end
    local playerCoords = GetEntityCoords(playerPed)
    local targetCoords = GetEntityCoords(targetPed)
    return #(playerCoords - targetCoords) > maxDistance
end

-- IMPROVEMENT: Check if target player is in a vehicle (server-side validation)
local function isPlayerInVehicle(targetSrc)
    local targetPed = GetPlayerPed(targetSrc)
    if not targetPed or targetPed == 0 then return false end
    return IsPedInAnyVehicle(targetPed, false)
end

-- IMPROVEMENT: Check if target player is a vehicle driver (server-side validation)
local function isPlayerDriver(targetSrc)
    local targetPed = GetPlayerPed(targetSrc)
    if not targetPed or targetPed == 0 then return false end
    local veh = GetVehiclePedIsIn(targetPed, false)
    if not veh or veh == 0 then return false end
    return GetPedInVehicleSeat(veh, -1) == targetPed
end

local function isPlayerRestrainedOrDown(targetSrc)
    local state = Player(targetSrc) and Player(targetSrc).state
    if handcuffState[targetSrc] == true then return true end
    if not state then return false end
    return state.ishandcuffed == true
        or state.handcuffed == true
        or state.dead == true
        or state.isDead == true
        or state.inlaststand == true
        or state.laststand == true
end

-- =========================
-- NEW (Requested): Suspect Interactions (Server-authoritative)
-- =========================

-- Why: suspect-affecting actions must be validated server-side to prevent abuse/desync.
-- Rules: job must be "police", must be on duty, and must be within 2.0m of suspect.

local escortPairs = {}
local gsrData = {}  -- IMPROVED: Better structure for GSR data
local GSR_DURATION_MS = 10 * 60 * 1000 -- 10 minutes

---IMPROVED: Flag player with GSR
---@param source integer Player server ID
local function flagPlayerWithGsr(source)
    if not source or source == 0 then return end
    gsrData[source] = GetGameTimer() + GSR_DURATION_MS
end

---IMPROVED: Check if player has active GSR
---@param source integer Player server ID
---@return boolean hasShotRecently
local function playerHasGsr(source)
    if not source or source == 0 then return false end
    
    local gsrExpires = gsrData[source]
    if not gsrExpires then return false end
    
    local currentTime = GetGameTimer()
    
    -- Expired, clean up
    if currentTime >= gsrExpires then
        gsrData[source] = nil
        return false
    end
    
    return true
end

-- NEW: Check if suspect is handcuffed (for escort validation)
lib.callback.register('qbx_police:server:isSuspectCuffed', function(src, targetSrc)
    if not isPoliceOnDutyBySpec(src) then
        return false
    end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then
        return false
    end
    if not getXPlayer(targetSrc) then return false end

    local state = Player(targetSrc) and Player(targetSrc).state
    return handcuffState[targetSrc] == true or (state and (state.ishandcuffed == true or state.handcuffed == true))
end)

-- NEW: Toggle cuff state (soft/hard) on the suspect.
lib.callback.register('qbx_police:server:toggleCuff', function(src, targetSrc, isSoft)
    if not isPoliceOnDutyBySpec(src) then
        return false, 'Police on-duty only.'
    end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then
        return false, 'Suspect is too far.'
    end

    local officer = getXPlayer(src)
    local suspect = getXPlayer(targetSrc)
    if not officer or not suspect then
        return false, 'Invalid suspect.'
    end

    -- Require handcuffs item (matches existing gameplay expectation)
    local cuffs = exports.ox_inventory:Search(src, 'count', 'handcuffs')
    if not cuffs or cuffs < 1 then
        return false, 'You need handcuffs.'
    end

    -- This existing client event toggles cuff/uncuff for the suspect.
    TriggerClientEvent('police:client:GetCuffed', targetSrc, src, isSoft == true)
    return true
end)

-- NEW: Toggle escort (attach/detach) on the suspect.
RegisterNetEvent('qbx_police:server:toggleEscort', function(targetSrc)
    local src = source
    if not isPoliceOnDutyBySpec(src) then return end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then return end

    -- IMPROVEMENT: Vehicle Restriction - Cannot escort players in vehicles
    if isPlayerInVehicle(targetSrc) then return end

    if not getXPlayer(targetSrc) then return end

    if escortPairs[targetSrc] == src then
        escortPairs[targetSrc] = nil
        TriggerClientEvent('police:client:DeEscort', targetSrc)
        return
    end

    escortPairs[targetSrc] = src
    TriggerClientEvent('qbx_police:client:toggleEscortFromMenu', targetSrc, src)
end)

-- NEW: Auto-detach escort if distance breaks / players disappear.
CreateThread(function()
    while true do
        Wait(1000)
        for targetSrc, officerSrc in pairs(escortPairs) do
            local officerPed = GetPlayerPed(officerSrc)
            local targetPed = GetPlayerPed(targetSrc)
            if officerPed == 0 or targetPed == 0 then
                escortPairs[targetSrc] = nil
                TriggerClientEvent('police:client:DeEscort', targetSrc)
            else
                local dist = #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed))
                if dist > 10.0 then
                    escortPairs[targetSrc] = nil
                    TriggerClientEvent('police:client:DeEscort', targetSrc)
                end
            end
        end
    end
end)

-- IMPROVED: GSR flagging when player fires weapon
RegisterNetEvent('qbx_police:server:playerFiredWeapon', function()
    local src = source
    flagPlayerWithGsr(src)
    -- Optional: Log for admin/monitoring
    -- print(('GSR flagged for player %d'):format(src))
end)

-- IMPROVED: GSR test callback used by the Police menu (validated)
lib.callback.register('qbx_police:server:gsrTest', function(src, targetSrc)
    if not isPoliceOnDutyBySpec(src) then
        return nil, 'Police on-duty only.'
    end

    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then
        return nil, 'Suspect is too far.'
    end

    if not getXPlayer(targetSrc) then
        return nil, 'Invalid suspect.'
    end

    if isPlayerInVehicle(targetSrc) then
        return nil, 'Cannot test GSR on a player in a vehicle.'
    end

    local hasGsr = playerHasGsr(targetSrc)

    -- Gloves reduce accuracy
    if hasGsr and not applyGloveModifier(targetSrc) then
        hasGsr = false
    end

    return hasGsr
end)


-- NEW: Place suspect into the officer-selected nearby vehicle (validated)
RegisterNetEvent('qbx_police:server:placeInVehicle', function(targetSrc, vehNetId)
    local src = source
    if not isPoliceOnDutyBySpec(src) then return end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then return end

    local veh = NetworkGetEntityFromNetworkId(vehNetId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return end

    local officerPed = GetPlayerPed(src)
    if officerPed == 0 then return end
    local targetPed = GetPlayerPed(targetSrc)
    if not targetPed or targetPed == 0 then return end
    
    -- SECURITY FIX #10: Validate BOTH officer-to-vehicle AND suspect-to-vehicle distances
    if #(GetEntityCoords(officerPed) - GetEntityCoords(veh)) > 2.0 then return end
    if #(GetEntityCoords(targetPed) - GetEntityCoords(veh)) > 2.0 then return end

    TriggerClientEvent('qbx_police:client:placeInVehicle', targetSrc, vehNetId)
end)

-- NEW: Remove suspect from their vehicle (validated)
RegisterNetEvent('qbx_police:server:removeFromVehicle', function(targetSrc)
    local src = source
    if not isPoliceOnDutyBySpec(src) then return end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then return end
    if not getXPlayer(targetSrc) then return end

    -- IMPROVEMENT: Driver Protection - Cannot remove drivers from vehicles
    if isPlayerDriver(targetSrc) then return end

    TriggerClientEvent('qbx_police:client:removeFromVehicle', targetSrc)
end)

AddEventHandler('playerDropped', function()
    local src = source
    gsrData[src] = nil
    escortPairs[src] = nil
        for targetSrc, officerSrc in pairs(escortPairs) do
        if officerSrc == src then
            escortPairs[targetSrc] = nil
            TriggerClientEvent('police:client:DeEscort', targetSrc)
        end
    end
end)

-- IMPROVED: Periodic cleanup for expired GSR entries (every 5 minutes)
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)  -- Every 5 minutes
        
        local currentTime = GetGameTimer()
        for playerId, expiresAt in pairs(gsrData) do
            if currentTime >= expiresAt then
                gsrData[playerId] = nil
            end
        end
    end
end)

lib.callback.register('qbx_police:server:getIdentification', function(src, targetSrc)
    if not isPoliceOnDutyBySpec(src) then return end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then return end

    local xTarget = getXPlayer(targetSrc)
    if not xTarget then return end

    local targetJob = getJob(xTarget) or {}
    local identifier = getIdentifier(xTarget)

    local sex = nil
    pcall(function() sex = xTarget.get('sex') end)
    local genderLabel = 'Unknown'
    if sex == 'm' or sex == 'M' then genderLabel = 'Male' end
    if sex == 'f' or sex == 'F' then genderLabel = 'Female' end

    local dob = 'Unknown'
    pcall(function() dob = xTarget.get('dateofbirth') or dob end)

    local licenses = {}
    if GetResourceState('esx_license') == 'started' and identifier and MySQL and MySQL.query and MySQL.query.await then
        local ok, rows = pcall(MySQL.query.await, 'SELECT type FROM user_licenses WHERE owner = ?', { identifier })
        if ok and type(rows) == 'table' then
            for i = 1, #rows do
                local t = rows[i] and rows[i].type
                if t then
                    licenses[#licenses + 1] = {
                        label = tostring(t),
                        status = 'Valid',
                        icon = 'fa-solid fa-circle-check'
                    }
                end
            end
        end
    end

    table.sort(licenses, function(a, b)
        return a.label < b.label
    end)

    return {
        name = getFullName(xTarget),
        fullname = getFullName(xTarget),
        phone = 'Unknown',
        job = targetJob.label or targetJob.name or 'Unemployed',
        position = targetJob.grade_label or tostring(targetJob.grade or 'Unknown'),
        dob = dob,
        gender = genderLabel,
        gang = 'None',
        warrant = 'Unknown',
        haswarrant = false,
        licenses = licenses,
    }
end)

lib.callback.register('qbx_police:server:getVehicleOwner', function(src, plate)
    if not isPoliceOnDutyBySpec(src) then return end
    if not plate or plate == '' then return end

    -- ESX default: owned_vehicles.owner -> users.firstname/lastname
    do
        local okVeh, ownerIdentifier = pcall(MySQL.scalar.await, 'SELECT owner FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        if okVeh and ownerIdentifier and ownerIdentifier ~= '' then
            local okUser, user = pcall(MySQL.single.await, 'SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { ownerIdentifier })
            if okUser and user then
                local ownerName = ((user.firstname or '') .. ' ' .. (user.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
                if ownerName == '' then ownerName = ownerIdentifier end
                return { plate = plate, owner = ownerName }
            end
            return { plate = plate, owner = ownerIdentifier }
        end
    end

    -- Fallback (QB schema) if your server still uses it
    local okCid, citizenid = pcall(MySQL.scalar.await, 'SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if okCid and citizenid then
        local okChar, charinfoJson = pcall(MySQL.scalar.await, 'SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        if okChar and charinfoJson and charinfoJson ~= '' then
            local okDecode, charinfo = pcall(json.decode, charinfoJson)
            if okDecode and type(charinfo) == 'table' then
                local ownerName = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
                if ownerName == '' then ownerName = citizenid end
                return { plate = plate, owner = ownerName }
            end
        end
        return { plate = plate, owner = citizenid }
    end

    return { plate = plate, owner = 'Unknown' }
end)

-- IMPROVED: Enhanced vehicle details callback (with model, stolen, flagged status)
lib.callback.register('qbx_police:server:getVehicleDetails', function(src, plate)
    if not isPoliceOnDutyBySpec(src) then return end
    if not plate or plate == '' then return nil end
    
    -- ESX default: owned_vehicles
    local okEsx, vehicleData = pcall(MySQL.single.await, 'SELECT * FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    
    if okEsx and not vehicleData then
        return {
            plate = plate,
            owner = 'Unknown',
            model = 'Unknown',
            stolen = false,
            flagged = isPlateFlagged(plate),
            expiration = 'Unknown',
            activePenalties = 'None'
        }
    end

    if okEsx and vehicleData then
        local ownerName = vehicleData.owner or 'Unknown'
        local okUser, user = pcall(MySQL.single.await, 'SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { vehicleData.owner })
        if okUser and user then
            ownerName = ((user.firstname or '') .. ' ' .. (user.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
            if ownerName == '' then ownerName = vehicleData.owner end
        end

        local modelName = 'Unknown'
        if vehicleData.vehicle and vehicleData.vehicle ~= '' then
            local okDecode, props = pcall(json.decode, vehicleData.vehicle)
            if okDecode and type(props) == 'table' then
                modelName = tostring(props.model or props.modelname or modelName)
            end
        end

        return {
            plate = plate,
            owner = ownerName,
            identifier = vehicleData.owner,
            model = modelName,
            stolen = false,
            flagged = isPlateFlagged(plate),
            purchaseDate = vehicleData.purchase_date or vehicleData.date or nil,
            expiration = 'Unknown',
            activePenalties = 'None'
        }
    end

    -- Fallback (QB schema)
    local okQb, qbData = pcall(MySQL.single.await, 'SELECT * FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not okQb or not qbData then
        return {
            plate = plate,
            owner = 'Unknown',
            model = 'Unknown',
            stolen = false,
            flagged = isPlateFlagged(plate),
            expiration = 'Unknown',
            activePenalties = 'None'
        }
    end

    local ownerName = qbData.citizenid
    local okChar, charinfoJson = pcall(MySQL.scalar.await, 'SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { qbData.citizenid })
    if okChar and charinfoJson and charinfoJson ~= '' then
        local okDecode, charinfo = pcall(json.decode, charinfoJson)
        if okDecode and type(charinfo) == 'table' then
            ownerName = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
            if ownerName == '' then ownerName = qbData.citizenid end
        end
    end

    return {
        plate = plate,
        owner = ownerName,
        citizenid = qbData.citizenid,
        stolen = qbData.stolen or false,
        flagged = isPlateFlagged(plate),
        purchaseDate = qbData.purchase_date,
        expiration = qbData.ins_expire or 'Unknown',
        activePenalties = qbData.active_fines or 'None'
    }
end)

-- ========================
-- NEW: Weapon License System
-- ========================

---Check if player has weapon license
---@param targetSrc integer Target player server ID
---@return boolean hasLicense
local function playerHasWeaponLicense(targetSrc)
    local xTarget = getXPlayer(targetSrc)
    if not xTarget then return false end

    local identifier = getIdentifier(xTarget)
    if GetResourceState('esx_license') == 'started' and identifier and MySQL and MySQL.scalar and MySQL.scalar.await then
        local ok, exists = pcall(MySQL.scalar.await, 'SELECT 1 FROM user_licenses WHERE owner = ? AND type = ? LIMIT 1', { identifier, 'weapon' })
        return ok and exists ~= nil
    end

    -- Fallback: no esx_license running
    return false
end

---Issue weapon license to player
---@param targetSrc integer Target player server ID
---@param issuedBySrc integer Police officer server ID
---@return boolean success
local function issueWeaponLicense(targetSrc, issuedBySrc)
    local xTarget = getXPlayer(targetSrc)
    local xOfficer = getXPlayer(issuedBySrc)
    if not xTarget or not xOfficer then return false end

    local officerJob = getJob(xOfficer)
    if not officerJob or officerJob.name ~= 'police' then return false end

    local identifier = getIdentifier(xTarget)
    if GetResourceState('esx_license') == 'started' and identifier and MySQL and MySQL.insert and MySQL.insert.await then
        -- user_licenses(owner, type)
        pcall(MySQL.insert.await, 'INSERT IGNORE INTO user_licenses (owner, type) VALUES (?, ?)', { identifier, 'weapon' })
    end

    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:AddItem(targetSrc, 'weaponlicense', 1)
    end
    
    -- Notify player
    TriggerClientEvent('ox_lib:notify', targetSrc, {
        title = 'Weapon License',
        description = 'You have been issued a weapon license.',
        type = 'success',
        duration = 5000
    })
    
    -- Notify officer
    notify(issuedBySrc, 'License issued successfully.', 'success', 'Weapon License')
    
    -- Log action
    print(('Officer %s (%d) issued weapon license to %s (%d)'):format(
        getFullName(xOfficer),
        issuedBySrc,
        getFullName(xTarget),
        targetSrc
    ))
    
    return true
end

--- Revoke weapon license from player
---@param targetSrc integer
---@param revokedBySrc integer
---@return boolean
local function revokeWeaponLicense(targetSrc, revokedBySrc)
    local xTarget = getXPlayer(targetSrc)
    local xOfficer = getXPlayer(revokedBySrc)
    if not xTarget or not xOfficer then return false end

    local officerJob = getJob(xOfficer)
    if not officerJob or officerJob.name ~= 'police' then
        return false
    end

    if not playerHasWeaponLicense(targetSrc) then
        return false
    end

    local identifier = getIdentifier(xTarget)
    if GetResourceState('esx_license') == 'started' and identifier and MySQL and MySQL.update and MySQL.update.await then
        pcall(MySQL.update.await, 'DELETE FROM user_licenses WHERE owner = ? AND type = ?', { identifier, 'weapon' })
    end

    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:RemoveItem(targetSrc, 'weaponlicense', 1)
    end

    -- Notify target
    notify(targetSrc, 'Your weapon license has been revoked by the police.', 'error', 'Weapon License Revoked')

    -- Server log
    lib.print.info(('[WEAPON LICENSE] %s (%d) revoked license of %s (%d)'):format(
        getFullName(xOfficer),
        revokedBySrc,
        getFullName(xTarget),
        targetSrc
    ))

    return true
end


-- Callback: Issue license
lib.callback.register('qbx_police:server:issueWeaponLicense', function(src, targetSrc)
    local officer = getXPlayer(src)
    if not officer then return false, 'Invalid officer.' end

    local job = getJob(officer)
    if not job or job.name ~= 'police' then
        return false, 'Invalid officer.'
    end

    -- Minimum grade level (Sergeant or above = grade 3)
    if (job.grade or 0) < 3 then
        return false, 'You are not authorized to issue weapon licenses.'
    end
    
    if not isPoliceOnDutyBySpec(src) then
        return false, 'Police on-duty only.'
    end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then
        return false, 'Player is too far.'
    end
    
    if playerHasWeaponLicense(targetSrc) then
        return false, 'Player already has a weapon license.'
    end
    
    local success = issueWeaponLicense(targetSrc, src)
    return success, success and 'License issued.' or 'Failed to issue license.'
end)

-- Callback: Revoke license
lib.callback.register('qbx_police:server:revokeWeaponLicense', function(src, targetSrc)
    local officer = getXPlayer(src)
    if not officer then return false, 'Invalid officer.' end

    local job = getJob(officer)
    if not job or job.name ~= 'police' then
        return false, 'Invalid officer.'
    end

    -- Minimum grade level (Sergeant or above = grade 3)
    if (job.grade or 0) < 3 then
        return false, 'You are not authorized to revoke weapon licenses.'
    end
    
    if not isPoliceOnDutyBySpec(src) then
        return false, 'Police on-duty only.'
    end
    if not targetSrc or isTargetTooFarStrict(src, targetSrc, 2.0) then
        return false, 'Player is too far.'
    end
    
    if not playerHasWeaponLicense(targetSrc) then
        return false, 'Player does not have a weapon license.'
    end
    
    local success = revokeWeaponLicense(targetSrc, src)
    return success, success and 'License revoked.' or 'Failed to revoke license.'
end)

-- Callback: Check if player has license
lib.callback.register('qbx_police:server:playerHasWeaponLicense', function(src, targetSrc)
    if not isPoliceOnDutyBySpec(src) then
        return false
    end
    
    return playerHasWeaponLicense(targetSrc)
end)

lib.callback.register('qbx_police:server:validateLockpickVehicle', function(src, netId)
    if not isPoliceOnDutyBySpec(src) then
        return false, 'Police on-duty only.'
    end

    if not netId then
        return false, 'No vehicle.'
    end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then
        return false, 'No vehicle.'
    end

    local srcPed = GetPlayerPed(src)
    if srcPed == 0 then
        return false, 'Invalid player.'
    end

    if #(GetEntityCoords(srcPed) - GetEntityCoords(veh)) > 5.0 then
        return false, 'Too far from vehicle.'
    end

    -- Optional inventory requirement: lockpick item
    local count = exports.ox_inventory:Search(src, 'count', 'lockpick')
    if not count or count < 1 then
        return false, 'You need a lockpick.'
    end

    -- Consume 1 lockpick per attempt (server-authoritative)
    exports.ox_inventory:RemoveItem(src, 'lockpick', 1)

    return true
end)

RegisterNetEvent('qbx_police:server:impoundFromMenu', function(netId, applyFine, fineAmount)
    local src = source
    if not isPoliceOnDutyBySpec(src) then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return end

    local srcPed = GetPlayerPed(src)
    if srcPed == 0 then return end
    if #(GetEntityCoords(srcPed) - GetEntityCoords(veh)) > 5.0 then return end

    local plate = getVehiclePlate(veh)
    if not plate or plate == '' then return end

    local price = 0
    if applyFine then
        price = tonumber(fineAmount) or 0
        if price < 0 then price = 0 end
    end

    local bodyDamage = math.ceil(GetVehicleBodyHealth(veh))
    local engineDamage = math.ceil(GetVehicleEngineHealth(veh))
    local totalFuel = GetVehicleFuelLevel(veh)

    -- This menu action behaves like "depot" (fullImpound=false) with optional fee.
    ImpoundWithPrice(price, bodyDamage, engineDamage, totalFuel, plate)
    DeleteEntity(veh)

    notify(src, 'Vehicle impounded.', 'success')
end)

-- Events
RegisterNetEvent('police:server:Radar', function(fine)
    local src = source
    local price  = sharedConfig.radars.speedFines[fine].fine
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end

    local amount = math.floor(tonumber(price) or 0)
    if amount <= 0 then return end

    local bank = xPlayer.getAccount('bank')
    if not bank or (bank.money or 0) < amount then return end
    xPlayer.removeAccountMoney('bank', amount)

    if GetResourceState('Renewed-Banking') == 'started' then
        exports['Renewed-Banking']:addAccountMoney('police', amount)
    end
    notify(src, locale('info.fine_received', amount), 'inform')
end)

RegisterNetEvent('police:server:policeAlert', function(text, camId, playerSource)
    if not playerSource then playerSource = source end
    local ped = GetPlayerPed(playerSource)
    local coords = GetEntityCoords(ped)
    local players = ESX.GetPlayers()
    for i = 1, #players do
        local targetSrc = players[i]
        if isLeoAndOnDuty(targetSrc) then
            if camId then
                local alertData = {title = locale('info.new_call'), coords = coords, description = text .. locale('info.camera_id') .. camId}
                TriggerClientEvent('qb-phone:client:addPoliceAlert', targetSrc, alertData)
                TriggerClientEvent('police:client:policeAlert', targetSrc, coords, text, camId)
            else
                local alertData = {title = locale('info.new_call'), coords = coords, description = text}
                TriggerClientEvent('qb-phone:client:addPoliceAlert', targetSrc, alertData)
                TriggerClientEvent('police:client:policeAlert', targetSrc, coords, text)
            end
        end
    end
end)

RegisterNetEvent('police:server:TakeOutImpound', function(plate, garage)
    local src = tonumber(source)
    if not src then return end
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    if #(playerCoords - sharedConfig.locations.impound[garage]) > 10.0 then return end

    Unimpound(plate)
    notify(src, locale('success.impound_vehicle_removed'), 'success')
end)

local function isTargetTooFar(src, targetSrc, maxDistance)
    maxDistance = maxDistance or 2.5
    local playerPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    local playerCoords = GetEntityCoords(playerPed)
    local targetCoords = GetEntityCoords(targetPed)
    if #(playerCoords - targetCoords) > maxDistance then
        return true
    end
end

lib.callback.register('police:server:CuffPlayer', function(src, cuffedSrc, isSoftcuff)
    if isTargetTooFar(src, cuffedSrc) then return end

    if not getXPlayer(src) then return end
    if not getXPlayer(cuffedSrc) then return end

    local cuffs = exports.ox_inventory:Search(src, 'count', 'handcuffs')
    if not cuffs or cuffs < 1 then return end

    TriggerClientEvent('police:client:GetCuffed', cuffedSrc, src, isSoftcuff)

    return true
end)

RegisterNetEvent('police:server:EscortPlayer', function(escortSrc)
    local src = source
    if isTargetTooFar(src, escortSrc) then return end

    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    if not getXPlayer(escortSrc) then return end

    local job = getJob(xPlayer)
    local canEscort = job and (isLeoJob(job.name) or isEmsJob(job.name))
    if canEscort or isPlayerRestrainedOrDown(escortSrc) then
        TriggerClientEvent('police:client:GetEscorted', escortSrc, src)
    else
        notify(src, locale('error.not_cuffed_dead'), 'error')
    end
end)

RegisterNetEvent('police:server:UncuffPlayer', function(targetSrc)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if not xPlayer or not job or not isLeoJob(job.name) then return end
    if not getXPlayer(targetSrc) then return end

    if not isPlayerRestrainedOrDown(targetSrc) then
        return notify(src, locale('error.not_cuffed_dead'), 'error')
    end

    TriggerClientEvent('police:client:GetCuffed', targetSrc, src, false)
end)

RegisterNetEvent('police:server:KidnapPlayer', function(kidnapedSrc)
    local src = source
    if isTargetTooFar(src, kidnapedSrc) then return end
    if not getXPlayer(src) then return end
    if not getXPlayer(kidnapedSrc) then return end

    if isPlayerRestrainedOrDown(kidnapedSrc) then
        TriggerClientEvent('police:client:GetKidnappedTarget', kidnapedSrc, src)
        TriggerClientEvent('police:client:GetKidnappedDragger', src, kidnapedSrc)
    else
        notify(src, locale('error.not_cuffed_dead'), 'error')
    end
end)

RegisterNetEvent('police:server:SetPlayerOutVehicle', function(targetSrc)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    if not getXPlayer(targetSrc) then return end
    if not isPlayerRestrainedOrDown(targetSrc) then
        return notify(src, locale('error.not_cuffed_dead'), 'error')
    end

    TriggerClientEvent('police:client:SetOutVehicle', targetSrc)
end)

RegisterNetEvent('police:server:PutPlayerInVehicle', function(targetSrc)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    if not getXPlayer(targetSrc) then return end
    if not isPlayerRestrainedOrDown(targetSrc) then
        return notify(src, locale('error.not_cuffed_dead'), 'error')
    end

    TriggerClientEvent('police:client:PutInVehicle', targetSrc)
end)

RegisterNetEvent('police:server:BillPlayer', function(targetSrc, price)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if not xPlayer or not job or not isLeoJob(job.name) then return end
    local xTarget = getXPlayer(targetSrc)
    if not xTarget then return end

    local amount = math.floor(tonumber(price) or 0)
    if amount <= 0 then return end

    local bank = xTarget.getAccount('bank')
    if not bank or (bank.money or 0) < amount then return end
    xTarget.removeAccountMoney('bank', amount)

    if GetResourceState('Renewed-Banking') == 'started' then
        exports['Renewed-Banking']:addAccountMoney('police', amount)
    end
    notify(targetSrc, locale('info.fine_received', amount), 'inform')
end)

RegisterNetEvent('police:server:JailPlayer', function(targetSrc, time)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if not xPlayer or not job or not isLeoJob(job.name) then return end
    
    local targetXPlayer = getXPlayer(targetSrc)
    if not targetXPlayer then return end

    local currentDate = os.date('*t')
    if currentDate.day == 31 then
        currentDate.day = 30
    end

    -- Track jailed player
    jailedPlayers[targetSrc] = {
        name = getFullName(targetXPlayer),
        jailTime = time
    }

    -- ESX jail is implementation-specific; we keep the existing client event hook.
    if GetResourceState('qbx_prison') == 'started' then
        exports.qbx_prison:JailPlayer(targetSrc, time)
    else
        TriggerClientEvent('police:client:SendToJail', targetSrc, time)
    end
    notify(src, locale('info.sent_jail_for', time), 'inform')
end)

RegisterNetEvent('police:server:UnjailPlayer', function(targetSrc)
    local src = source
    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if not xPlayer or not job or not isLeoJob(job.name) then return end
    if not getXPlayer(targetSrc) then return end

    -- Release player from jail using prison resource
    if GetResourceState('qbx_prison') == 'started' then
        exports.qbx_prison:UnjailPlayer(targetSrc)
    else
        TriggerClientEvent('police:client:ReleaseFromJail', targetSrc)
    end
    
    -- Remove from tracked jailed players
    jailedPlayers[targetSrc] = nil
    
    -- Teleport player to police station
    local policeCoords = vector3(425.4, -979.5, 29.4)  -- Default police station
    TriggerClientEvent('police:client:TeleportToPolice', targetSrc, policeCoords)
    
    notify(src, locale('info.suspect_released') or 'Suspect has been released from jail.', 'success')
    notify(targetSrc, locale('info.you_released') or 'You have been released from jail.', 'success')
end)

-- Callback to get list of jailed players
lib.callback.register('police:server:getJailedPlayers', function(source)
    local src = source
    local xPlayer = getXPlayer(src)
    local job = getJob(xPlayer)
    if not xPlayer or not job or not isLeoJob(job.name) then
        return {}
    end
    
    -- Convert tracked jailed players to list format
    local jailedList = {}
    for serverId, playerData in pairs(jailedPlayers) do
        table.insert(jailedList, {
            serverId = tonumber(serverId),
            name = playerData.name,
            jailTime = playerData.jailTime
        })
    end
    
    return jailedList
end)

-- Clean up jailed players on player drop
AddEventHandler('playerDropped', function(reason)
    local src = source
    jailedPlayers[src] = nil
end)

RegisterNetEvent('police:server:SetHandcuffStatus', function(isHandcuffed)
    local src = source
    if not getXPlayer(src) then return end
    handcuffState[src] = isHandcuffed == true
    local p = Player(src)
    if p and p.state then
        p.state:set('ishandcuffed', handcuffState[src], true)
    end
end)

RegisterNetEvent('heli:spotlight', function(state)
    TriggerClientEvent('heli:spotlight', -1, source, state)
end)

RegisterNetEvent('police:server:FlaggedPlateTriggered', function(radar, plate, street)
    local src = tonumber(source)
    if not src then return end
    local coords = GetEntityCoords(GetPlayerPed(src))
    local players = ESX.GetPlayers()
    for i = 1, #players do
        local targetSrc = players[i]
        if isLeoAndOnDuty(targetSrc) then
            local alertData = {title = locale('info.new_call'), coords = coords, description = locale('info.plate_triggered', plate, street, radar)}
            TriggerClientEvent('qb-phone:client:addPoliceAlert', targetSrc, alertData)
            TriggerClientEvent('police:client:policeAlert', targetSrc, coords, locale('info.plate_triggered_blip', radar))
        end
    end
end)

RegisterNetEvent('police:server:SearchPlayer', function(targetSrc)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    if not getXPlayer(targetSrc) then return end

    notify(src, locale('info.searched_success'), 'inform')
    notify(targetSrc, locale('info.being_searched'), 'inform')
end)

RegisterNetEvent('police:server:SeizeCash', function(targetSrc)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    local xOfficer = getXPlayer(src)
    local xTarget = getXPlayer(targetSrc)
    if not xOfficer or not xTarget then return end

    local moneyAmount = xTarget.getMoney()
    if not moneyAmount or moneyAmount <= 0 then return end

    xTarget.removeMoney(moneyAmount)
    exports.ox_inventory:AddItem(src, 'moneybag', 1, { cash = moneyAmount })
    notify(targetSrc, locale('info.cash_confiscated'), 'inform')
end)

RegisterNetEvent('police:server:RobPlayer', function(targetSrc)
    local src = source
    if isTargetTooFar(src, targetSrc) then return end

    local xRobber = getXPlayer(src)
    local xTarget = getXPlayer(targetSrc)
    if not xRobber or not xTarget then return end

    local money = xTarget.getMoney()
    if not money or money <= 0 then return end

    xTarget.removeMoney(money)
    xRobber.addMoney(money)

    notify(targetSrc, locale('info.cash_robbed', money), 'inform')
    notify(src, locale('info.stolen_money', money), 'inform')
end)

RegisterNetEvent('police:server:Impound', function(plate, fullImpound, price, body, engine, fuel)
    local src = source
    price = price or 0
    if not fullImpound then
        ImpoundWithPrice(price, body, engine, fuel, plate)
        notify(src, locale('info.vehicle_taken_depot', price), 'inform')
    else
        ImpoundForever(body, engine, fuel, plate)
        notify(src, locale('info.vehicle_seized'), 'inform')
    end
end)

RegisterNetEvent('evidence:server:UpdateStatus', function(data)
    playerStatus[source] = data
end)

RegisterNetEvent('evidence:server:CreateBloodDrop', function(citizenid, bloodtype, coords)
    local bloodId = generateId(bloodDrops)
    bloodDrops[bloodId] = {
        dna = citizenid,
        bloodtype = bloodtype
    }
    TriggerClientEvent('evidence:client:AddBlooddrop', -1, bloodId, citizenid, bloodtype, coords)
end)

RegisterNetEvent('evidence:server:CreateFingerDrop', function(coords)
    local fingerId = generateId(fingerDrops)
    local fp = ensureFingerprints(source)
    fingerDrops[fingerId] = fp
    TriggerClientEvent('evidence:client:AddFingerPrint', -1, fingerId, fp, coords)
end)

RegisterNetEvent('evidence:server:ClearBlooddrops', function(bloodDropList)
    if not bloodDropList or not next(bloodDropList) then return end
    for _, v in pairs(bloodDropList) do
        TriggerClientEvent('evidence:client:RemoveBlooddrop', -1, v)
        bloodDrops[v] = nil
    end
end)

RegisterNetEvent('evidence:server:AddBlooddropToInventory', function(bloodId, bloodInfo)
    local src = source
    local playerName = getFullName(getXPlayer(src))
    local streetName = bloodInfo.street
    local bloodType = bloodInfo.bloodtype
    local bloodDNA = bloodInfo.dnalabel
    local metadata = {}
    metadata.type = 'Blood Evidence'
    metadata.description = 'DNA ID: '..bloodDNA
    metadata.description = metadata.description..'\n\nBlood Type: '..bloodType
    metadata.description = metadata.description..'\n\nCollected By: '..playerName
    metadata.description = metadata.description..'\n\nCollected At: '..streetName
    if not exports.ox_inventory:RemoveItem(src, 'empty_evidence_bag', 1) then
        return notify(src, locale('error.have_evidence_bag'), 'error')
    end
    if exports.ox_inventory:AddItem(src, 'filled_evidence_bag', 1, metadata) then
        TriggerClientEvent('evidence:client:RemoveBlooddrop', -1, bloodId)
        bloodDrops[bloodId] = nil
    end
end)

RegisterNetEvent('evidence:server:AddFingerprintToInventory', function(fingerId, fingerInfo)
    local src = source
    local playerName = getFullName(getXPlayer(src))
    local streetName = fingerInfo.street
    local fingerprint = fingerInfo.fingerprint
    local metadata = {}
    metadata.type = 'Fingerprint Evidence'
    metadata.description = 'Fingerprint ID: '..fingerprint
    metadata.description = metadata.description..'\n\nCollected By: '..playerName
    metadata.description = metadata.description..'\n\nCollected At: '..streetName
    if not exports.ox_inventory:RemoveItem(src, 'empty_evidence_bag', 1) then
        return notify(src, locale('error.have_evidence_bag'), 'error')
    end
    if exports.ox_inventory:AddItem(src, 'filled_evidence_bag', 1, metadata) then
        TriggerClientEvent('evidence:client:RemoveFingerprint', -1, fingerId)
        fingerDrops[fingerId] = nil
    end
end)

RegisterNetEvent('evidence:server:CreateCasing', function(weapon, serial, coords)
    local casingId = generateId(casings)
    local serieNumber = exports.ox_inventory:GetCurrentWeapon(source).metadata.serial
    if not serieNumber then
    serieNumber = serial
    end
    TriggerClientEvent('evidence:client:AddCasing', -1, casingId, weapon, coords, serieNumber)
end)

RegisterNetEvent('police:server:UpdateCurrentCops', function()
    local amount = 0
    local players = ESX.GetPlayers()
    if updatingCops then return end
    updatingCops = true
    for i = 1, #players do
        if isLeoAndOnDuty(players[i]) then
            amount += 1
        end
    end
    TriggerClientEvent('police:SetCopCount', -1, amount)
    updatingCops = false
end)

RegisterNetEvent('evidence:server:ClearCasings', function(casingList)
    if casingList and next(casingList) then
        for _, v in pairs(casingList) do
            TriggerClientEvent('evidence:client:RemoveCasing', -1, v)
            casings[v] = nil
        end
    end
end)

RegisterNetEvent('evidence:server:AddCasingToInventory', function(casingId, casingInfo)
    local src = source
    local playerName = getFullName(getXPlayer(src))
    local streetName = casingInfo.street
    local ammoType = casingInfo.ammolabel
    local serialNumber = casingInfo.serie
    local metadata = {}
    metadata.type = 'Casing Evidence'
    metadata.description = 'Ammo Type: '..ammoType
    metadata.description = metadata.description..'\n\nSerial #: '..serialNumber
    metadata.description = metadata.description..'\n\nCollected By: '..playerName
    metadata.description = metadata.description..'\n\nCollected At: '..streetName
    if not exports.ox_inventory:RemoveItem(src, 'empty_evidence_bag', 1) then
        return notify(src, locale('error.have_evidence_bag'), 'error')
    end
    if exports.ox_inventory:AddItem(src, 'filled_evidence_bag', 1, metadata) then
        TriggerClientEvent('evidence:client:RemoveCasing', -1, casingId)
        casings[casingId] = nil
    end
end)

RegisterNetEvent('police:server:showFingerprint', function(playerId)
    TriggerClientEvent('police:client:showFingerprint', playerId, source)
    TriggerClientEvent('police:client:showFingerprint', source, playerId)
end)

RegisterNetEvent('police:server:showFingerprintId', function(sessionId)
    local fid = ensureFingerprints(source)
    TriggerClientEvent('police:client:showFingerprintId', sessionId, fid)
    TriggerClientEvent('police:client:showFingerprintId', source, fid)
end)

AddEventHandler('onServerResourceStart', function(resource)
    if resource ~= 'ox_inventory' then return end

    -- ox_inventory groups table: { jobName = minGrade }
    local jobs = {
        police = 0,
        sheriff = 0,
        state = 0,
        fib = 0,
    }

    for i = 1, #sharedConfig.locations.trash do
        exports.ox_inventory:RegisterStash(('policetrash_%s'):format(i), 'Police Trash', 300, 4000000, nil, jobs, sharedConfig.locations.trash[i])
    end
    exports.ox_inventory:RegisterStash('policelocker', 'Police Locker', 30, 100000, true)
end)

-- Threads
CreateThread(function()
    Wait(1000)
    for i = 1, #sharedConfig.locations.trash do
        exports.ox_inventory:ClearInventory(('policetrash_%s'):format(i))
    end
    while true do
        Wait(1000 * 60 * 10)
        local curCops = 0
        local players = ESX.GetPlayers()
        for i = 1, #players do
            if isLeoAndOnDuty(players[i]) then
                curCops += 1
            end
        end
        TriggerClientEvent('police:SetCopCount', -1, curCops)
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        updateBlips()
    end
end)

-- ========================
-- EXPORTS: Escort System
-- ========================

---Start escorting a player
---@param officerSrc integer Police officer server ID
---@param targetSrc integer Suspect/target server ID
---@return boolean success, string? message
exports('startEscort', function(officerSrc, targetSrc)
    -- Validate officer is police on-duty
    if not officerSrc or not targetSrc then
        return false, 'Invalid parameters'
    end
    
    local officer = getXPlayer(officerSrc)
    local officerJob = getJob(officer)
    if not officer or not officerJob or officerJob.name ~= 'police' or not getOnDuty(officerSrc, officerJob.name) then
        return false, 'Officer not on-duty'
    end
    
    -- Validate distance
    if isTargetTooFarStrict(officerSrc, targetSrc, 2.0) then
        return false, 'Target too far (max 2.0 units)'
    end
    
    -- Validate target not in vehicle
    if isPlayerInVehicle(targetSrc) then
        return false, 'Target cannot be in a vehicle'
    end
    
    -- Validate target exists
    local suspect = getXPlayer(targetSrc)
    if not suspect then
        return false, 'Target player not found'
    end
    
    -- If already escorting, stop
    if escortPairs[targetSrc] == officerSrc then
        escortPairs[targetSrc] = nil
        TriggerClientEvent('police:client:DeEscort', targetSrc)
        return true, 'Escort stopped'
    end
    
    -- Start escort
    escortPairs[targetSrc] = officerSrc
    TriggerClientEvent('qbx_police:client:toggleEscortFromMenu', targetSrc, officerSrc)
    return true, 'Escort started'
end)

---Stop escorting a player
---@param targetSrc integer Suspect/target server ID
---@return boolean success, string? message
exports('stopEscort', function(targetSrc)
    if not targetSrc then
        return false, 'Invalid target'
    end
    
    if not escortPairs[targetSrc] then
        return false, 'Target is not being escorted'
    end
    
    escortPairs[targetSrc] = nil
    TriggerClientEvent('police:client:DeEscort', targetSrc)
    return true, 'Escort stopped'
end)

---Check if a player is being escorted
---@param targetSrc integer Suspect/target server ID
---@return boolean isEscorted
exports('isPlayerEscorted', function(targetSrc)
    if not targetSrc then return false end
    return escortPairs[targetSrc] ~= nil
end)

---Get the officer escorting a player
---@param targetSrc integer Suspect/target server ID
---@return integer? officerSrc The escorting officer's server ID, or nil
exports('getEscortingOfficer', function(targetSrc)
    if not targetSrc then return nil end
    return escortPairs[targetSrc]
end)

---Get all players being escorted
---@return table escortList {targetSrc = officerSrc, ...}
exports('getEscortList', function()
    return escortPairs
end)
