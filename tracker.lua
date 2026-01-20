ESX = exports['es_extended']:getSharedObject()

local PlayerData = {}
local OnDuty = false

-- Tracked entities
local trackedPlayers = {}
local trackedVehicles = {}
local vehicleBlips = {}

-- =========================
-- PLAYER DATA / DUTY
-- =========================
RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerData.job = job
end)

-- Your duty system must trigger this
RegisterNetEvent('esx_police:setDuty', function(state)
    OnDuty = state
end)

local function isPoliceOnDuty()
    return PlayerData.job
        and PlayerData.job.name == 'police'
        and OnDuty == true
end

-- =========================
-- VEHICLE TRACKERS
-- =========================
RegisterNetEvent('police:client:updateVehicleTrackers', function(trackedPlates)
    trackedVehicles = trackedPlates or {}
end)

-- Immediate metadata sync hint (handled by polling loop)
RegisterNetEvent('police:client:SetTracker', function()
    -- no-op; polling handles updates
end)

-- =========================
-- MAIN TRACKING LOOP
-- =========================
CreateThread(function()
    while true do
        Wait(500)

        if not isPoliceOnDuty() then
            -- Clear all blips if not police on duty
            for _, blip in pairs(trackedPlayers) do
                RemoveBlip(blip)
            end
            trackedPlayers = {}

            for _, blip in pairs(vehicleBlips) do
                RemoveBlip(blip)
            end
            vehicleBlips = {}

            goto continue
        end

        -- =========================
        -- PLAYER ANKLE TRACKERS
        -- =========================
        for _, playerId in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(playerId)
            if ped ~= 0 then
                local serverId = GetPlayerServerId(playerId)
                if serverId then
                    local hasTracker = lib.callback.await(
                        'police:server:getTrackerStatus',
                        false,
                        serverId
                    )

                    if hasTracker then
                        local coords = GetEntityCoords(ped)
                        print(('[TRACKER BLIP] Player %s has tracker, creating/updating blip'):format(serverId))

                        if not trackedPlayers[serverId] then
                            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
                            SetBlipSprite(blip, 464)
                            SetBlipColour(blip, 1)
                            SetBlipDisplay(blip, 4)
                            SetBlipAsShortRange(blip, false)
                            SetBlipScale(blip, 0.8)
                            BeginTextCommandSetBlipName('STRING')
                            AddTextComponentString('Tracked Suspect')
                            EndTextCommandSetBlipName(blip)

                            trackedPlayers[serverId] = blip
                            print(('[TRACKER BLIP] Created new blip for player %s'):format(serverId))
                        else
                            SetBlipCoords(
                                trackedPlayers[serverId],
                                coords.x,
                                coords.y,
                                coords.z
                            )
                        end
                    elseif trackedPlayers[serverId] then
                        RemoveBlip(trackedPlayers[serverId])
                        trackedPlayers[serverId] = nil
                    end
                end
            end
        end

        -- =========================
        -- VEHICLE TRACKERS
        -- =========================
        for plate, _ in pairs(trackedVehicles) do
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if GetVehicleNumberPlateText(veh) == plate then
                    local coords = GetEntityCoords(veh)
                    local model = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                    local name = GetLabelText(model)

                    if not vehicleBlips[plate] then
                        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
                        SetBlipSprite(blip, 227)
                        SetBlipColour(blip, 2)
                        SetBlipDisplay(blip, 4)
                        SetBlipAsShortRange(blip, false)
                        SetBlipScale(blip, 0.8)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString(name ~= 'NULL' and name or 'Tracked Vehicle')
                        EndTextCommandSetBlipName(blip)

                        vehicleBlips[plate] = blip
                    else
                        SetBlipCoords(
                            vehicleBlips[plate],
                            coords.x,
                            coords.y,
                            coords.z
                        )
                    end
                    break
                end
            end
        end

        -- Remove stale vehicle blips
        for plate, blip in pairs(vehicleBlips) do
            if not trackedVehicles[plate] then
                RemoveBlip(blip)
                vehicleBlips[plate] = nil
            end
        end

        ::continue::
    end
end)

-- =========================
-- CLEANUP
-- =========================
AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    for _, blip in pairs(trackedPlayers) do
        RemoveBlip(blip)
    end

    for _, blip in pairs(vehicleBlips) do
        RemoveBlip(blip)
    end
end)
