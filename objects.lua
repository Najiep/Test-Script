local sharedConfig = require 'config.shared'

-- ESX Legacy
local ESX = exports['es_extended']:getSharedObject()

-- If you use an external duty script, set this convar to true.
-- When enabled, we will read Player(src).state.onDuty when present.
local USE_EXTERNAL_DUTY = GetConvarInt('qbx_police:useExternalDuty', 0) == 1

-- NEW (security hardening): server-side validation for object placement.
-- Keeps existing behavior, but prevents non-LEO/off-duty clients from spawning props.
local function checkLeoAndOnDuty(src)
    if not src then return false end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    local job
    local ok = pcall(function()
        job = xPlayer.getJob()
    end)
    if not ok or not job or not job.name then return false end

    local jobName = job.name
    local isLeo = (jobName == 'police' or jobName == 'sheriff' or jobName == 'state' or jobName == 'fib')
    if not isLeo then return false end

    if not USE_EXTERNAL_DUTY then
        return true
    end

    local state = Player(src) and Player(src).state
    if state and state.onDuty ~= nil then
        return state.onDuty == true
    end

    -- Fallback: if no duty state is available, keep ESX-default behavior (treated as on-duty).
    return true
end

local function ensureGlobalStateTables()
    GlobalState.spikeStrips = GlobalState.spikeStrips or {}
    GlobalState.policeObjects = GlobalState.policeObjects or {}
    GlobalState.fixedCoords = GlobalState.fixedCoords or {}
end

local function requestModelServer(modelHash)
    if type(modelHash) == 'string' then
        modelHash = joaat(modelHash)
    end
    if not modelHash or modelHash == 0 then return nil end
    if not IsModelInCdimage(modelHash) then return nil end

    RequestModel(modelHash)
    local ok = lib.waitFor(function()
        if HasModelLoaded(modelHash) then return true end
    end, ('Failed to load model %s'):format(modelHash), sharedConfig.timeout)

    if not ok then return nil end
    return modelHash
end

---Spawns object
---@param modelHash string
---@param coords vector4
---@param zOffset number
---@param isFixed boolean?
---@return table? objects
---@return number? object
local function spawnObject(objects, modelHash, coords, zOffset, isFixed)
    ensureGlobalStateTables()
    objects = objects or {}

    local loadedHash = requestModelServer(modelHash)
    if not loadedHash then return nil, nil end

    local object = CreateObject(loadedHash, coords.x, coords.y, coords.z - zOffset, true, true, false)
    SetEntityHeading(object, coords.w)
    FreezeEntityPosition(object, true)

    local exists = lib.waitFor(function ()
        if DoesEntityExist(object) then return true end
    end, ('Failed to spawn prop %s'):format(modelHash), sharedConfig.timeout)

    if exists then
        local netid = NetworkGetNetworkIdFromEntity(object)
        objects[#objects+1] = netid
        if isFixed then
            local coordsState = GlobalState.fixedCoords or {}
            coordsState[netid] = GetEntityCoords(object)
            GlobalState.fixedCoords = coordsState
        end

        SetModelAsNoLongerNeeded(loadedHash)
        return objects, netid
    end

    SetModelAsNoLongerNeeded(loadedHash)
end

---Spawns spike strip
---@param coords vector3
---@param heading number
lib.callback.register('police:server:spawnSpikeStrip', function(_, coords, heading)
    local src = source
    if not checkLeoAndOnDuty(src) then return nil, 'error.on_duty_police_only' end
    ensureGlobalStateTables()
    if #(GlobalState.spikeStrips or {}) > sharedConfig.maxSpikes then return nil, 'error.no_spikestripe' end
    local objects, netid = spawnObject(GlobalState.spikeStrips, `P_ld_stinger_s`,
                                       vector4(coords.x, coords.y, coords.z, heading), 1, true)
    GlobalState.spikeStrips = objects

    return netid
end)

---Spawns police object
---@param modelHash string
---@param coords vector3
---@param heading number
lib.callback.register('police:server:spawnObject', function(_, modelHash, coords, heading)
    local src = source
    if not checkLeoAndOnDuty(src) then return nil, 'error.on_duty_police_only' end
    ensureGlobalStateTables()
    local objects, netid = spawnObject(GlobalState.policeObjects, modelHash,
                                       vector4(coords.x, coords.y, coords.z, heading), 0.3)
    GlobalState.policeObjects = objects

    return netid
end)

local function despawnObject(objects, index)
    if not objects or not index then return objects end
    local netId = objects[index]
    if not netId then return objects end

    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
    objects[index] = objects[#objects]
    objects[#objects] = nil
    return objects
end

RegisterNetEvent('police:server:despawnSpikeStrip', function(index)
    local src = source
    if not checkLeoAndOnDuty(src) then return end
    ensureGlobalStateTables()
    index = tonumber(index)
    if not index or index < 1 or index > #(GlobalState.spikeStrips or {}) then return end
    GlobalState.spikeStrips = despawnObject(GlobalState.spikeStrips, index)
end)

RegisterNetEvent('police:server:despawnObject', function(index)
    local src = source
    if not checkLeoAndOnDuty(src) then return end
    ensureGlobalStateTables()
    index = tonumber(index)
    if not index or index < 1 or index > #(GlobalState.policeObjects or {}) then return end
    GlobalState.policeObjects = despawnObject(GlobalState.policeObjects, index)
end)

AddEventHandler('onResourceStart', function (resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    GlobalState.spikeStrips = {}
    GlobalState.policeObjects = {}
    GlobalState.fixedCoords = {}
end)

AddEventHandler('onResourceStop', function (resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    local spikeStrips = GlobalState.spikeStrips or {}
    for i = 1, #spikeStrips do
        DeleteEntity(NetworkGetEntityFromNetworkId(spikeStrips[i]))
    end

    local policeObjects = GlobalState.policeObjects or {}
    for i = 1, #policeObjects do
        DeleteEntity(NetworkGetEntityFromNetworkId(policeObjects[i]))
    end

    GlobalState.spikeStrips = nil
    GlobalState.policeObjects = nil
    GlobalState.fixedCoords = nil
end)
