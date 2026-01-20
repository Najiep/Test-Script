-- qbx_police/server/rob.lua (ESX Legacy)

local ESX = exports['es_extended']:getSharedObject()

local MAX_ROB_DISTANCE = 3.0
local DEBUG = GetConvarInt('qbx_police_debug_rob', 0) == 1

---@param src number
---@param type 'inform'|'success'|'error'
---@param description string
local function notify(src, type, description)
    TriggerClientEvent('ox_lib:notify', src, {
        type = type,
        description = description,
    })
end

---@param playerId number
---@return table|nil
local function getPlayerState(playerId)
    local p = Player(playerId)
    return p and p.state or nil
end

---@param playerId number
---@return any
local function getXPlayer(playerId)
    if ESX and ESX.GetPlayerFromId then
        return ESX.GetPlayerFromId(playerId)
    end
    return nil
end

---@param xPlayer any
---@param keys string[]
---@return boolean
local function xPlayerHasTrue(xPlayer, keys)
    if not xPlayer or type(xPlayer.get) ~= 'function' then return false end
    for i = 1, #keys do
        local ok, val = pcall(xPlayer.get, xPlayer, keys[i])
        if ok and val == true then
            return true
        end
    end
    return false
end

---@param ped number
---@param playerId number
local function isDead(ped, playerId)
    if not ped or ped == 0 then return false end
    
    -- Check entity health
    local health = GetEntityHealth(ped)
    if health <= 0 then return true end
    
    -- ESX fallback (statebag / commonly-used flags)
    if playerId then
        local state = getPlayerState(playerId)
        if state and (state.dead == true or state.isDead == true or state.isdead == true) then return true end

        local xPlayer = getXPlayer(playerId)
        if xPlayerHasTrue(xPlayer, { 'dead', 'isDead', 'isdead' }) then return true end
    end
    
    return false
end

---@param ped number
---@param playerId number
local function isRestrained(ped, playerId)
    if not ped or ped == 0 then return false end

    -- Entity statebag (works with many cuff scripts)
    local ent = Entity(ped)
    local entState = ent and ent.state or nil
    if entState and (entState.isCuffed == true or entState.handcuffed == true or entState.isHandcuffed == true or entState.escorted == true) then
        return true
    end
    
    -- Player statebag / ESX fallback (server-visible)
    if playerId then
        local state = getPlayerState(playerId)
        if state and (state.isCuffed == true or state.handcuffed == true or state.isHandcuffed == true or state.escorted == true) then return true end

        local xPlayer = getXPlayer(playerId)
        if xPlayerHasTrue(xPlayer, { 'ishandcuffed', 'handcuffed', 'isHandcuffed', 'isCuffed' }) then return true end
    end
    
    return false
end

local function handleRobPlayer(target, handsUp)
    local src = source
    if not target or type(target) ~= 'number' then return end
    if src == target then return end

    if GetPlayerPing(target) <= 0 then return end

    local srcPed = GetPlayerPed(src)
    local tgtPed = GetPlayerPed(target)
    if not srcPed or srcPed == 0 or not tgtPed or tgtPed == 0 then return end
    if not DoesEntityExist(srcPed) or not DoesEntityExist(tgtPed) then return end

    -- 🔒 Distance check (ANTI-EXPLOIT)
    local dist = #(GetEntityCoords(srcPed) - GetEntityCoords(tgtPed))
    if dist > MAX_ROB_DISTANCE then return end

    local dead = isDead(tgtPed, target)
    local restrained = isRestrained(tgtPed, target)
    local hands = handsUp == true -- client hint

    -- Debug output to verify detection
    if DEBUG then
        print(string.format('^2[ROB] Target Status - Dead: %s, Restrained: %s, HandsUp: %s^7',
            tostring(dead), tostring(restrained), tostring(hands)))
    end

    if not (dead or restrained or hands) then
        notify(src, 'error', 'Target must be hands up, restrained, or dead')
        return
    end

    -- ✅ Open target inventory
    exports.ox_inventory:forceOpenInventory(src, 'player', target)
end

-- Keep the original event name for compatibility with your current client
RegisterNetEvent('qbx_police:server:robPlayer', handleRobPlayer)

-- ESX-style alias (optional)
--RegisterNetEvent('esx_policejob:server:robPlayer', handleRobPlayer)
