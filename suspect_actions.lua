--[[ 
    Suspect Interactions (ESX Legacy)

    Notes:
    - These events are triggered by server-authoritative logic
      (menu, commands, ox_target, etc.).
    - Client only performs attach / vehicle actions.
]]

ESX = exports['es_extended']:getSharedObject()

-- Ensure global escort state exists
IsEscorted = IsEscorted or false

-- =========================
-- ESCORT TOGGLE (NO CUFF REQUIRED)
-- =========================
RegisterNetEvent('qbx_police:client:toggleEscortFromMenu', function(officerServerId)
    if not officerServerId then return end

    local officerPlayer = GetPlayerFromServerId(officerServerId)
    if officerPlayer == -1 then return end

    local officerPed = GetPlayerPed(officerPlayer)
    if not DoesEntityExist(officerPed) then return end

    if not IsEscorted then
        IsEscorted = true

        local offset = GetOffsetFromEntityInWorldCoords(officerPed, 0.0, 0.45, 0.0)
        SetEntityCoords(cache.ped, offset.x, offset.y, offset.z, true, false, false, false)

        AttachEntityToEntity(
            cache.ped,
            officerPed,
            11816,         -- SKEL_Pelvis
            0.45, 0.45, 0.0,
            0.0, 0.0, 0.0,
            false, false, false, false,
            2, true
        )
    else
        IsEscorted = false
        DetachEntity(cache.ped, true, false)
    end

    -- Optional compatibility with hospital / EMS scripts
    TriggerEvent('hospital:client:isEscorted', IsEscorted)
end)

-- =========================
-- PLACE INTO VEHICLE
-- =========================
RegisterNetEvent('qbx_police:client:placeInVehicle', function(vehicleNetId)
    if not vehicleNetId then return end

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end

    for seat = GetVehicleMaxNumberOfPassengers(vehicle), 0, -1 do
        if IsVehicleSeatFree(vehicle, seat) then
            IsEscorted = false
            TriggerEvent('hospital:client:isEscorted', false)

            ClearPedTasks(cache.ped)
            DetachEntity(cache.ped, true, false)
            Wait(50)

            SetPedIntoVehicle(cache.ped, vehicle, seat)
            return
        end
    end
end)

-- =========================
-- REMOVE FROM VEHICLE
-- =========================
RegisterNetEvent('qbx_police:client:removeFromVehicle', function()
    if not cache.vehicle then return end

    local vehicle = cache.vehicle
    TaskLeaveVehicle(cache.ped, vehicle, 16)

    -- Move player slightly away to prevent clipping
    SetTimeout(750, function()
        if not DoesEntityExist(vehicle) then return end
        local pos = GetOffsetFromEntityInWorldCoords(vehicle, 1.5, 0.0, 0.0)
        SetEntityCoords(cache.ped, pos.x, pos.y, pos.z, false, false, false, false)
    end)
end)
