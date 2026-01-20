local config = require 'config.client'
local animation = require 'client.modules.animations'
local isEscorting = false
local cuffType = 1
local isHandcuffed = false
local isEscorted = false
local escortedBy = nil
local isLoggedIn = LocalPlayer.state.isLoggedIn == true

local DISABLED_CONTROLS = {
    21,  -- Sprint
    24,  -- Attack
    257, -- Attack 2
    25,  -- Aim
    263, -- Melee Attack 1
    45,  -- Reload
    22,  -- Jump
    44,  -- Cover
    37,  -- Select Weapon
    23,  -- Also 'enter'?
    288, -- Disable phone
    289, -- Inventory
    170, -- Animations
    167, -- Job
    26,  -- Disable looking behind
    73,  -- Disable clearing animation
    199, -- Disable pause screen
    59,  -- Disable steering in vehicle
    71,  -- Disable driving forward in vehicle
    72,  -- Disable reversing in vehicle
    36,  -- Disable going stealth
    264, -- Disable melee
    257, -- Disable melee
    140, -- Disable melee
    141, -- Disable melee
    142, -- Disable melee
    143, -- Disable melee
    75   -- Disable exit vehicle
}

local function getLocalBagName()
    local serverId = cache and cache.serverId or GetPlayerServerId(cache.playerId)
    return ('player:%s'):format(serverId)
end

local function notify(message, ntype)
    lib.notify({
        description = message,
        type = ntype or 'inform'
    })
end

local isLocalPlayerDeadOrInLaststand

local cuffThreadActive = false

local function updateControlState()
    if isHandcuffed or isEscorted then
        lib.disableControls:Add(DISABLED_CONTROLS)
    else
        lib.disableControls:Remove(DISABLED_CONTROLS)
    end
end

local function startCuffLoop()
    if cuffThreadActive then return end
    cuffThreadActive = true

    CreateThread(function()
        -- Initial play
        animation.arrestIdle(cache.ped, cuffType)
        
        while isHandcuffed do
            if isLocalPlayerDeadOrInLaststand() then
                animation.stop(cache.ped)
                Wait(500)
                goto continue
            end

            -- Restart animation if stopped (more aggressive)
            if not IsEntityPlayingAnim(cache.ped, 'mp_arresting', 'idle', 3) then
                animation.arrestIdle(cache.ped, cuffType)
            end

            ::continue::
            Wait(500)  -- Check every 500ms instead of 1000ms for better responsiveness
        end

        animation.stop(cache.ped)
        cuffThreadActive = false
    end)
end

local function applyCuffState(value, isSoft)
    isHandcuffed = value == true
    if isHandcuffed then
        cuffType = isSoft and 48 or 16
        startCuffLoop()
    end
    updateControlState()
end

local function applyEscortState(value)
    isEscorted = value == true
    updateControlState()
end

AddStateBagChangeHandler('isCuffed', nil, function(bagName, _, value)
    if bagName ~= getLocalBagName() then return end
    applyCuffState(value, cuffType == 48)
end)

local Suspect = {}

function Suspect.searchNearby()
    TriggerEvent('police:client:SearchPlayer')
end

function Suspect.seizeCash()
    TriggerEvent('police:client:SeizeCash')
end

function Suspect.rob()
    TriggerEvent('police:client:RobPlayer')
end

function Suspect.jail()
    TriggerEvent('police:client:JailPlayer')
end

function Suspect.unjail()
    TriggerEvent('police:client:UnjailPlayer')
end

function Suspect.bill()
    TriggerEvent('police:client:BillPlayer')
end

function Suspect.putInVehicle()
    TriggerEvent('police:client:PutPlayerInVehicle')
end

function Suspect.setOutVehicle()
    TriggerEvent('police:client:SetPlayerOutVehicle')
end

function Suspect.escort()
    TriggerEvent('police:client:EscortPlayer')
end

function Suspect.kidnap()
    TriggerEvent('police:client:KidnapPlayer')
end

function Suspect.cuffSoft()
    TriggerEvent('police:client:CuffPlayerSoft')
end

function Suspect.cuffHard()
    TriggerEvent('police:client:CuffPlayer')
end

AddStateBagChangeHandler('escortedBy', nil, function(bagName, _, value)
    if bagName ~= getLocalBagName() then return end
    escortedBy = value
    applyEscortState(value ~= nil)
end)

AddStateBagChangeHandler('isLoggedIn', nil, function(bagName, _, value)
    if bagName ~= getLocalBagName() then return end
    isLoggedIn = value == true
end)

updateControlState()

exports('IsHandcuffed', function()
    return isHandcuffed
end)

exports('suspect', function()
    return Suspect
end)

local function isTargetDead(playerId)
    return lib.callback.await('police:server:isPlayerDead', false, playerId)
end

isLocalPlayerDeadOrInLaststand = function()
    if IsEntityDead(cache.ped) then return true end
    if LocalPlayer and LocalPlayer.state then
        return LocalPlayer.state.isDead == true
            or LocalPlayer.state.dead == true
            or LocalPlayer.state.inlaststand == true
            or LocalPlayer.state.laststand == true
    end
    return false
end

local function handCuffAnimation()
    animation.cuff(cache.ped)
end

local function getCuffedAnimation(playerId)
    animation.getCuffed(cache.ped, playerId)
end


RegisterNetEvent('police:client:SetOutVehicle', function()
    if not cache.vehicle or cache.vehicle == 0 or not DoesEntityExist(cache.vehicle) then return end
    TaskLeaveVehicle(cache.ped, cache.vehicle, 16)
end)

RegisterNetEvent('police:client:PutInVehicle', function()
    if not isHandcuffed and not isEscorted then return end

    local vehicle = nil
    local closestDist = 15.0
    local coords = GetEntityCoords(cache.ped)

    -- Find closest valid vehicle with better detection
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and not IsEntityDead(veh) then
            local vehCoords = GetEntityCoords(veh)
            local dist = #(coords - vehCoords)
            if dist < closestDist then
                closestDist = dist
                vehicle = veh
            end
        end
    end

    if not vehicle or not DoesEntityExist(vehicle) then
        notify(locale('error.none_nearby'), 'error')
        return
    end

    -- Try to find first available seat (driver first, then passengers)
    for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) do
        if IsVehicleSeatFree(vehicle, i) then
            applyEscortState(false)
            escortedBy = nil
            LocalPlayer.state:set('escortedBy', nil, true)
            TriggerEvent('hospital:client:isEscorted', isEscorted)
            ClearPedTasks(cache.ped)
            DetachEntity(cache.ped, true, false)
            Wait(100)
            SetPedIntoVehicle(cache.ped, vehicle, i)
            notify(locale('success.in_vehicle') or 'Placed in vehicle', 'success')
            return
        end
    end

    notify(locale('error.no_seat') or 'No seats available', 'error')
end)

---Check for closest player within distance or 2.5 units
---@param distance number?
---@return number? playerId
---@return number? playerPed
local function getClosestPlayer(distance)
    local coords = GetEntityCoords(cache.ped)
    local player, playerPed = lib.getClosestPlayer(coords, distance or 2.5)
    if not player then
        notify(locale('error.none_nearby'), 'error')
        return
    end

    return player, playerPed
end

RegisterNetEvent('police:client:SearchPlayer', function()
    local player = getClosestPlayer()
    if not player then return end
    local playerId = GetPlayerServerId(player)
    exports.ox_inventory:openNearbyInventory()
    TriggerServerEvent('police:server:SearchPlayer', playerId)
end)

RegisterNetEvent('police:client:SeizeCash', function()
    local player = getClosestPlayer()
    if not player then return end
    local playerId = GetPlayerServerId(player)
    TriggerServerEvent('police:server:SeizeCash', playerId)
end)

RegisterNetEvent('police:client:RobPlayer', function()
    local player, playerPed = getClosestPlayer()
    if not player or not playerPed then return end
    local playerId = GetPlayerServerId(player)

    if not (IsEntityPlayingAnim(playerPed, 'missminuteman_1ig_2', 'handsup_base', 3)
        or IsEntityPlayingAnim(playerPed, 'mp_arresting', 'idle', 3)
        or isTargetDead(playerId))
    then
        return notify(locale('error.no_rob'), 'error')
    end

    if lib.progressCircle({
        duration = math.random(5000, 7000),
        position = 'bottom',
        label = locale('progressbar.robbing'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
            mouse = false
        },
        anim = {
            dict = 'random@shop_robbery',
            clip = 'robbery_action_b',
            flags = 16
        }
    })
    then
        local playerCoords = GetEntityCoords(playerPed)
        local pos = GetEntityCoords(cache.ped)
        if #(pos - playerCoords) < 2.5 then
            StopAnimTask(cache.ped, 'random@shop_robbery', 'robbery_action_b', 1.0)
            exports.ox_inventory:openNearbyInventory()
            TriggerServerEvent('police:server:RobPlayer', playerId)
        else
            notify(locale('error.none_nearby'), 'error')
        end
    else
        StopAnimTask(cache.ped, 'random@shop_robbery', 'robbery_action_b', 1.0)
        notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('police:client:JailPlayer', function()
    local player = getClosestPlayer()
    if not player then return end
    local playerId = GetPlayerServerId(player)
    local playerName = GetPlayerName(player)
    
    -- Show confirmation dialog with player name
    local confirmed = lib.alertDialog({
        header = 'Jail Suspect',
        content = 'Are you sure you want to jail ' .. playerName .. '?',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Jail',
            cancel = 'Cancel'
        }
    })
    
    if not confirmed then return end
    
    -- Ask for jail time
    local dialog = lib.inputDialog(locale('info.jail_time_input'), {
        {type = 'number', label = locale('info.time_months'), min = 0}
    })
    if dialog and dialog[1] > 0 then
        TriggerServerEvent('police:server:JailPlayer', playerId, dialog[1])
    else
        notify(locale('error.time_higher'), 'error')
    end
end)

RegisterNetEvent('police:client:UnjailPlayer', function()
    local player = getClosestPlayer()
    if not player then return end
    local playerId = GetPlayerServerId(player)
    local playerName = GetPlayerName(player)
    
    -- Show confirmation dialog with player name
    local confirmed = lib.alertDialog({
        header = 'Unjail Suspect',
        content = 'Are you sure you want to unjail ' .. playerName .. '?',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Unjail',
            cancel = 'Cancel'
        }
    })
    
    if confirmed then
        TriggerServerEvent('police:server:UnjailPlayer', playerId)
    end
end)

RegisterNetEvent('police:client:BillPlayer', function()
    local player = getClosestPlayer()
    if not player then return end
    local playerId = GetPlayerServerId(player)
    local dialog = lib.inputDialog(locale('info.bill'), {
        {type = 'number', label = locale('info.amount'), min = 0}
    })
    if dialog and dialog[1] > 0 then
        TriggerServerEvent('police:server:BillPlayer', playerId, dialog[1])
    else
        notify(locale('error.time_higher'), 'error')
    end
end)

local function triggerIfHandsFree(eventName)
    local player = getClosestPlayer()
    if not player then return end
    local playerId = GetPlayerServerId(player)
    if isHandcuffed or isEscorted then return end
    TriggerServerEvent(eventName, playerId)
end

RegisterNetEvent('police:client:PutPlayerInVehicle', function()
    triggerIfHandsFree('police:server:PutPlayerInVehicle')
end)

RegisterNetEvent('police:client:SetPlayerOutVehicle', function()
    triggerIfHandsFree('police:server:SetPlayerOutVehicle')
end)

RegisterNetEvent('police:client:EscortPlayer', function()
    triggerIfHandsFree('police:server:EscortPlayer')
end)

RegisterNetEvent('police:client:KidnapPlayer', function()
    local player, playerPed = getClosestPlayer()
    if not player or not playerPed then return end
    local playerId = GetPlayerServerId(player)
    if IsPedInAnyVehicle(playerPed, false) or isHandcuffed or isEscorted then return end
    TriggerServerEvent('police:server:KidnapPlayer', playerId)
end)

RegisterNetEvent('police:client:CuffPlayerSoft', function()
    if IsPedRagdoll(cache.ped) then return end
    local player, playerPed = getClosestPlayer(1.5)
    if not player or not playerPed then return end
    local playerId = GetPlayerServerId(player)

    if IsPedInAnyVehicle(playerPed, false) or cache.vehicle then
        return notify(locale('error.vehicle_cuff'), 'error')
    end

    if lib.callback.await('police:server:CuffPlayer', false, playerId, true) then
        handCuffAnimation()
    end
end)

RegisterNetEvent('police:client:CuffPlayer', function()
    if IsPedRagdoll(cache.ped) then return end
    local player, playerPed = getClosestPlayer()
    if not player or not playerPed then return end

    if exports.ox_inventory:Search('count', config.handcuffItems) == 0 then
        return notify(locale('error.no_cuff'), 'error')
    end

    local playerId = GetPlayerServerId(player)

    if IsPedInAnyVehicle(playerPed, false) or cache.vehicle then
        return notify(locale('error.vehicle_cuff'), 'error')
    end

    if lib.callback.await('police:server:CuffPlayer', false, playerId, false) then
        handCuffAnimation()
    end
end)

RegisterNetEvent('police:client:GetEscorted', function(playerId)
    if not (isLocalPlayerDeadOrInLaststand() or isHandcuffed) then return end

    if not isEscorted then
        applyEscortState(true)
        escortedBy = playerId
        LocalPlayer.state:set('escortedBy', playerId, true)
        local dragger = GetPlayerPed(GetPlayerFromServerId(playerId))
        local offset = GetOffsetFromEntityInWorldCoords(dragger, 0.0, 0.45, 0.0)
        SetEntityCoords(cache.ped, offset.x, offset.y, offset.z, true, false, false, false)
        AttachEntityToEntity(cache.ped, dragger, 11816, 0.45, 0.45, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    else
        applyEscortState(false)
        escortedBy = nil
        LocalPlayer.state:set('escortedBy', nil, true)
        DetachEntity(cache.ped, true, false)
    end
    TriggerEvent('hospital:client:isEscorted', isEscorted)
end)

RegisterNetEvent('police:client:DeEscort', function()
    applyEscortState(false)
    escortedBy = nil
    LocalPlayer.state:set('escortedBy', nil, true)
    TriggerEvent('hospital:client:isEscorted', isEscorted)
    DetachEntity(cache.ped, true, false)
end)

RegisterNetEvent('police:client:GetKidnappedTarget', function(playerId)
    if isLocalPlayerDeadOrInLaststand() or isHandcuffed then
        if not isEscorted then
            applyEscortState(true)
            escortedBy = playerId
            LocalPlayer.state:set('escortedBy', playerId, true)
            local dragger = GetPlayerPed(GetPlayerFromServerId(playerId))
            animation.fireMansCarry(cache.ped, playerId)
            AttachEntityToEntity(cache.ped, dragger, 0, 0.27, 0.15, 0.63, 0.5, 0.5, 0.0, false, false, false, false, 2, false)
        else
            applyEscortState(false)
            escortedBy = nil
            LocalPlayer.state:set('escortedBy', nil, true)
            DetachEntity(cache.ped, true, false)
            ClearPedTasksImmediately(cache.ped)
        end
        TriggerEvent('hospital:client:isEscorted', isEscorted)
    end
end)

RegisterNetEvent('police:client:GetKidnappedDragger', function()
    if not isEscorting then
        animation.cameraMan(cache.ped)
        isEscorting = true
    else
        animation.stop(cache.ped)
        isEscorting = false
    end
    TriggerEvent('hospital:client:SetEscortingState', isEscorting)
    TriggerEvent('qb-kidnapping:client:SetKidnapping', isEscorting)
end)

RegisterNetEvent('police:client:GetCuffed', function(playerId, isSoftcuff)
    if not isHandcuffed then
        TriggerServerEvent('police:server:SetHandcuffStatus', true)
        applyCuffState(true, isSoftcuff)
        LocalPlayer.state:set('isCuffed', true, true)
        animation.stop(cache.ped)
        if cache.weapon ~= `WEAPON_UNARMED` then
            SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
        end
        if not isSoftcuff then
            cuffType = 16
            notify(locale('info.cuff'), 'success')
        else
            if config.breakCuffs == true then
                local isSuccess = lib.skillCheck(config.breakCuffsDifficulty, config.breakCuffsKeys)
                if isSuccess then
                    TriggerServerEvent('police:server:SetHandcuffStatus', false)
                    applyCuffState(false, false)
                    LocalPlayer.state:set('isCuffed', false, true)
                    animation.stop(cache.ped)
                    notify(locale('success.escapedcuff'), 'success')
                    return
                end
            end
            cuffType = 48
            notify(locale('info.cuffed_walk'), 'success')
        end
        getCuffedAnimation(playerId)
    else
        applyEscortState(false)
        escortedBy = nil
        LocalPlayer.state:set('escortedBy', nil, true)
        TriggerEvent('hospital:client:isEscorted', isEscorted)
        DetachEntity(cache.ped, true, false)
        TriggerServerEvent('police:server:SetHandcuffStatus', false)
        applyCuffState(false, false)
        LocalPlayer.state:set('isCuffed', false, true)
        animation.stop(cache.ped)
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'Uncuff', 0.2)
        notify(locale('success.uncuffed'), 'success')
    end
end)
RegisterNetEvent('police:client:TeleportToPolice', function(coords)
    if not coords then
        coords = vector3(425.4, -979.5, 29.4)  -- Default police station
    end
    
    SetEntityCoords(cache.ped, coords.x, coords.y, coords.z, false, false, false, true)
    notify('You have been released and transported to the police station.', 'success')
end)