--[[
    NEW FEATURE (Requested): F5 Police Interaction Menu
    - Opens with /policemenu (RegisterCommand + RegisterKeyMapping)
    - ox_lib context menus (nested)
    - Access: job must be "police" and on duty
    - Calls existing qbx_police logic where available (billing, jail, impound, objects)
]]

local sharedConfig = require 'config.shared'

local ESX = exports['es_extended']:getSharedObject()
local playerData = ESX.PlayerData or {}

-- If you use an external duty script, set this convar to true.
-- Expected statebag key: LocalPlayer.state.onDuty (boolean)
local USE_EXTERNAL_DUTY = GetConvarInt('qbx_police:useExternalDuty', 0) == 1

AddEventHandler('esx:playerLoaded', function(xPlayer)
    playerData = xPlayer or {}
end)

RegisterNetEvent('esx:setJob', function(job)
    playerData.job = job
end)

-- NEW (Requested): cached suspect target for Suspect Interactions menu
local cachedSuspect = nil

---Access rules as per spec: job == "police" and on duty
local function getJob()
    return (ESX.PlayerData and ESX.PlayerData.job) or (playerData and playerData.job)
end

local function isOnDuty()
    -- ESX default: no built-in duty. We treat players as on-duty unless you provide a duty system.
    if not USE_EXTERNAL_DUTY then return true end
    local state = LocalPlayer and LocalPlayer.state
    if state and state.onDuty ~= nil then
        return state.onDuty == true
    end
    return true
end

local function isPoliceOnDuty()
    local job = getJob()
    return job and job.name == 'police' and isOnDuty()
end

local function ensurePoliceOnDuty()
    if isPoliceOnDuty() then return true end
    lib.notify({ title = 'Police', description = 'You must be police and on duty.', type = 'error' })
    return false
end

local function getVehiclePlate(veh)
    if not veh or veh == 0 then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    return tostring(plate):gsub('^%s+', ''):gsub('%s+$', '')
end

local function getClosestPlayerServerId()
    local coords = GetEntityCoords(cache.ped)
    local playerId = lib.getClosestPlayer(coords, 2.0)
    if not playerId then
        lib.notify({ title = 'Police', description = 'No nearby suspect.', type = 'error' })
        return nil
    end

    return GetPlayerServerId(playerId)
end

-- NEW (Requested): cache suspect when Suspect menu opens
local function cacheClosestSuspectOrNotify()
    local coords = GetEntityCoords(cache.ped)
    local playerId = lib.getClosestPlayer(coords, 2.0)
    if not playerId then
        lib.notify({ title = 'Police', description = 'No nearby suspect.', type = 'error' })
        return nil
    end

    cachedSuspect = {
        serverId = GetPlayerServerId(playerId),
        cachedAt = GetGameTimer(),
    }

    return cachedSuspect.serverId
end

-- NEW (Requested): revalidate suspect before each action
local function getValidatedCachedSuspectServerId()
    if not cachedSuspect or not cachedSuspect.serverId then
        lib.notify({ title = 'Police', description = 'No suspect selected.', type = 'error' })
        return nil
    end

    local playerId = GetPlayerFromServerId(cachedSuspect.serverId)
    if not playerId or playerId == -1 then
        lib.notify({ title = 'Police', description = 'Suspect not available.', type = 'error' })
        return nil
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        lib.notify({ title = 'Police', description = 'Suspect not available.', type = 'error' })
        return nil
    end

    if #(cache.coords - GetEntityCoords(ped)) > 2.0 then  -- PERFORMANCE FIX #3: Use cached coords
        lib.notify({ title = 'Police', description = 'Suspect is too far.', type = 'error' })
        return nil
    end

    return cachedSuspect.serverId
end

-- NEW (Requested): small local cuff animation snippet for officer
local function playOfficerCuffAnim()
    lib.requestAnimDict('mp_arrest_paired')
    TaskPlayAnim(cache.ped, 'mp_arrest_paired', 'cop_p2_back_right', 3.0, 3.0, -1, 48, 0, false, false, false)
    Wait(3500)
    
    -- PERFORMANCE FIX #5: Ensure animation cleanup even if interrupted
    if IsEntityPlayingAnim(cache.ped, 'mp_arrest_paired', 'cop_p2_back_right', 3) then
        TaskPlayAnim(cache.ped, 'mp_arrest_paired', 'exit', 3.0, 3.0, -1, 48, 0, false, false, false)
        Wait(500)
    end
    
    RemoveAnimDict('mp_arrest_paired')
end

-- Utility: get closest vehicle within range
local function getClosestVehicleOrNotify()
    local vehicle = lib.getClosestVehicle(cache.coords)  -- PERFORMANCE FIX #3: Use cached coords
    if not vehicle or not DoesEntityExist(vehicle) then
        lib.notify({ title = 'Police', description = 'No nearby vehicle.', type = 'error' })
        return nil
    end

    if #(cache.coords - GetEntityCoords(vehicle)) > 5.0 then  -- PERFORMANCE FIX #3: Use cached coords
        lib.notify({ title = 'Police', description = 'No nearby vehicle.', type = 'error' })
        return nil
    end

    return vehicle
end

-- IMPROVEMENT: Check if target player is in a vehicle
local function isPlayerInVehicle(playerId)
    if not playerId or playerId == -1 then return false end
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then return false end
    return IsPedInAnyVehicle(ped, false)
end

-- IMPROVEMENT: Check if target player is the driver of a vehicle
local function isPlayerDriver(playerId)
    if not playerId or playerId == -1 then return false end
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then return false end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return false end
    -- Seat -1 is driver seat
    return GetPedInVehicleSeat(veh, -1) == ped
end

-- =========================
-- NEW MENU: Suspect Interactions
-- =========================

local function actionToggleSoftCuff()
    if not ensurePoliceOnDuty() then return end
    
    -- SECURITY FIX #9: Client-side pre-check: Do we have handcuffs?
    local hasHandcuffs = exports.ox_inventory:Search('count', 'handcuffs') > 0
    if not hasHandcuffs then
        lib.notify({ title = 'Police', description = 'You need handcuffs.', type = 'error' })
        return
    end
    
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    -- IMPROVEMENT: Vehicle Restriction - Cannot cuff players in vehicles
    local playerId = GetPlayerFromServerId(targetSrc)
    if isPlayerInVehicle(playerId) then
        lib.notify({ title = 'Police', description = 'Cannot cuff a player in a vehicle.', type = 'error' })
        return
    end

    local ok, err = lib.callback.await('qbx_police:server:toggleCuff', false, targetSrc, true)
    if not ok then
        lib.notify({ title = 'Police', description = err or 'Unable to cuff suspect.', type = 'error' })
        return
    end

    playOfficerCuffAnim()
end

local function actionToggleHardCuff()
    if not ensurePoliceOnDuty() then return end
    
    -- SECURITY FIX #9: Client-side pre-check: Do we have handcuffs?
    local hasHandcuffs = exports.ox_inventory:Search('count', 'handcuffs') > 0
    if not hasHandcuffs then
        lib.notify({ title = 'Police', description = 'You need handcuffs.', type = 'error' })
        return
    end
    
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    -- IMPROVEMENT: Vehicle Restriction - Cannot cuff players in vehicles
    local playerId = GetPlayerFromServerId(targetSrc)
    if isPlayerInVehicle(playerId) then
        lib.notify({ title = 'Police', description = 'Cannot cuff a player in a vehicle.', type = 'error' })
        return
    end

    local ok, err = lib.callback.await('qbx_police:server:toggleCuff', false, targetSrc, false)
    if not ok then
        lib.notify({ title = 'Police', description = err or 'Unable to cuff suspect.', type = 'error' })
        return
    end

    playOfficerCuffAnim()
end

local function actionToggleEscort()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    local targetPlayer = GetPlayerFromServerId(cachedSuspect.serverId)
    if not targetPlayer or targetPlayer == -1 then
        lib.notify({ title = 'Police', description = 'Suspect not available.', type = 'error' })
        return
    end
    
    local targetPed = GetPlayerPed(targetPlayer)
    if not targetPed or targetPed == 0 then
        lib.notify({ title = 'Police', description = 'Suspect not available.', type = 'error' })
        return
    end

    -- IMPROVEMENT: Vehicle Restriction - Cannot escort players in vehicles
    if isPlayerInVehicle(targetPlayer) then
        lib.notify({ title = 'Police', description = 'Cannot escort a player in a vehicle.', type = 'error' })
        return
    end

    -- Check if suspect is handcuffed (server-side metadata check)
    local isCuffed = lib.callback.await('qbx_police:server:isSuspectCuffed', false, targetSrc)
    if not isCuffed then
        lib.notify({ title = 'Escort', description = 'Suspect must be handcuffed to escort.', type = 'error' })
        return
    end

    TriggerServerEvent('qbx_police:server:toggleEscort', targetSrc)
end

local function actionGsrTest()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    local targetPlayer = GetPlayerFromServerId(targetSrc)
    if not targetPlayer or targetPlayer == -1 then
        lib.notify({ title = 'Police', description = 'Suspect not available.', type = 'error' })
        return
    end

    -- IMPROVEMENT: Vehicle Restriction - Cannot GSR test players in vehicles
    if isPlayerInVehicle(targetPlayer) then
        lib.notify({ title = 'Police', description = 'Cannot GSR test a player in a vehicle.', type = 'error' })
        return
    end

    local done = lib.progressCircle({
        duration = 2500,
        position = 'bottom',
        label = 'Performing GSR test...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, mouse = false },
        anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base', flags = 1 },
    })

    if not done then
        lib.notify({ title = 'GSR Test', description = 'Cancelled.', type = 'error' })
        return
    end

    local result, err = lib.callback.await('qbx_police:server:gsrTest', false, targetSrc)
    if err then
        lib.notify({ title = 'GSR Test', description = err, type = 'error' })
        return
    end

    if result then
        lib.notify({ title = 'GSR Test', description = 'POSITIVE: Gunshot residue detected.', type = 'error' })
    else
        lib.notify({ title = 'GSR Test', description = 'NEGATIVE: No residue detected.', type = 'success' })
    end
end

local function actionPlaceInVehicle()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    local vehicle = getClosestVehicleOrNotify()
    if not vehicle then return end
    local vehNetId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent('qbx_police:server:placeInVehicle', targetSrc, vehNetId)
end

local function actionRemoveFromVehicle()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    local targetPlayer = GetPlayerFromServerId(targetSrc)
    if not targetPlayer or targetPlayer == -1 then
        lib.notify({ title = 'Police', description = 'Suspect not available.', type = 'error' })
        return
    end

    -- IMPROVEMENT: Driver Protection - Cannot remove drivers from vehicles
    if isPlayerDriver(targetPlayer) then
        lib.notify({ title = 'Police', description = 'Cannot remove a driver from their vehicle.', type = 'error' })
        return
    end

    TriggerServerEvent('qbx_police:server:removeFromVehicle', targetSrc)
end

-- NEW: Toggle tracker on suspect
local function actionToggleTracker()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    TriggerServerEvent('police:server:SetTracker', targetSrc)
end

-- NEW: Issue tracker on person
local function actionIssueTrackerPerson()
    if not ensurePoliceOnDuty() then return end
    local coords = GetEntityCoords(cache.ped)
    local playerId = lib.getClosestPlayer(coords, 2.0)
    if not playerId then
        lib.notify({ title = 'Police', description = 'No nearby person.', type = 'error' })
        return
    end
    
    local targetSrc = GetPlayerServerId(playerId)
    TriggerServerEvent('police:server:SetTracker', targetSrc)
end

-- NEW: Remove tracker from person
local function actionRemoveTrackerPerson()
    if not ensurePoliceOnDuty() then return end
    local coords = GetEntityCoords(cache.ped)
    local playerId = lib.getClosestPlayer(coords, 2.0)
    if not playerId then
        lib.notify({ title = 'Police', description = 'No nearby person.', type = 'error' })
        return
    end
    
    local targetSrc = GetPlayerServerId(playerId)
    TriggerServerEvent('police:server:SetTracker', targetSrc)
end

-- NEW: Issue tracker on vehicle
local function actionIssueTrackerVehicle()
    if not ensurePoliceOnDuty() then return end
    local vehicle = getClosestVehicleOrNotify()
    if not vehicle then return end
    
    local plate = getVehiclePlate(vehicle)
    if not plate or plate == '' then
        lib.notify({ title = 'Police', description = 'Unable to get vehicle plate.', type = 'error' })
        return
    end
    
    TriggerServerEvent('police:server:setVehicleTracker', plate, true)
    lib.notify({ title = 'Police', description = 'Vehicle tracker placed on plate: ' .. plate, type = 'success' })
end

-- NEW: Remove tracker from vehicle
local function actionRemoveTrackerVehicle()
    if not ensurePoliceOnDuty() then return end
    local vehicle = getClosestVehicleOrNotify()
    if not vehicle then return end
    
    local plate = getVehiclePlate(vehicle)
    if not plate or plate == '' then
        lib.notify({ title = 'Police', description = 'Unable to get vehicle plate.', type = 'error' })
        return
    end
    
    TriggerServerEvent('police:server:setVehicleTracker', plate, false)
    lib.notify({ title = 'Police', description = 'Vehicle tracker removed from plate: ' .. plate, type = 'success' })
end

-- NEW: Open tracker person menu
local function openTrackerPersonMenu()
    if not ensurePoliceOnDuty() then return end

    lib.registerContext({
        id = 'qbx_police:policemenu:tracker:person',
        title = 'Tracker the Person',
        menu = 'qbx_police:policemenu:tracker',
        options = {
            {
                title = 'Issue Tracker',
                description = 'Place ankle tracker on closest person.',
                icon = 'fa-solid fa-check',
                onSelect = actionIssueTrackerPerson
            },
            {
                title = 'Remove Tracker',
                description = 'Remove ankle tracker from closest person.',
                icon = 'fa-solid fa-xmark',
                onSelect = actionRemoveTrackerPerson
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:tracker'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:tracker:person')
end

-- NEW: Open tracker vehicle menu
local function openTrackerVehicleMenu()
    if not ensurePoliceOnDuty() then return end

    lib.registerContext({
        id = 'qbx_police:policemenu:tracker:vehicle',
        title = 'Tracker the Vehicle',
        menu = 'qbx_police:policemenu:tracker',
        options = {
            {
                title = 'Issue Tracker',
                description = 'Place tracker on nearby vehicle.',
                icon = 'fa-solid fa-check',
                onSelect = actionIssueTrackerVehicle
            },
            {
                title = 'Remove Tracker',
                description = 'Remove tracker from nearby vehicle.',
                icon = 'fa-solid fa-xmark',
                onSelect = actionRemoveTrackerVehicle
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:tracker'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:tracker:vehicle')
end

-- NEW: Open main tracker management menu
local function openTrackerMenu()
    if not ensurePoliceOnDuty() then return end

    lib.registerContext({
        id = 'qbx_police:policemenu:tracker',
        title = 'Tracker Management',
        menu = 'qbx_police:policemenu:main',
        options = {
            {
                title = 'Tracker the Person',
                description = 'Place/remove tracker on person.',
                icon = 'fa-solid fa-user',
                onSelect = openTrackerPersonMenu
            },
            {
                title = 'Tracker the Vehicle',
                description = 'Place/remove tracker on vehicle.',
                icon = 'fa-solid fa-car',
                onSelect = openTrackerVehicleMenu
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:main'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:tracker')
end

-- NEW: Issue weapon license to suspect
local function actionIssueWeaponLicense()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    -- Check if player already has license
    local hasLicense = lib.callback.await('qbx_police:server:playerHasWeaponLicense', false, targetSrc)
    if hasLicense then
        lib.notify({ title = 'Police', description = 'Player already has a weapon license.', type = 'error' })
        return
    end

    -- Confirm action
    local confirm = lib.alertDialog({
        header = 'Issue Weapon License',
        content = 'Are you sure you want to issue a weapon license to this player?',
        centered = true,
        cancel = true
    })

    if confirm ~= 'confirm' then return end

    local ok, msg = lib.callback.await('qbx_police:server:issueWeaponLicense', false, targetSrc)

    if ok then
        lib.notify({ title = 'Police', description = msg, type = 'success' })
    else
        lib.notify({ title = 'Police', description = msg or 'Failed to issue license.', type = 'error' })
    end
end

-- NEW: Revoke weapon license from suspect
local function actionRevokeWeaponLicense()
    if not ensurePoliceOnDuty() then return end
    local targetSrc = getValidatedCachedSuspectServerId()
    if not targetSrc then return end

    -- Check if player has license
    local hasLicense = lib.callback.await('qbx_police:server:playerHasWeaponLicense', false, targetSrc)
    if not hasLicense then
        lib.notify({ title = 'Police', description = 'Player does not have a weapon license.', type = 'error' })
        return
    end

    -- Confirm action
    local confirm = lib.alertDialog({
        header = 'Revoke Weapon License',
        content = 'Are you sure you want to revoke this player\'s weapon license?',
        centered = true,
        cancel = true
    })

    if confirm ~= 'confirm' then return end

    local ok, msg = lib.callback.await('qbx_police:server:revokeWeaponLicense', false, targetSrc)

    if ok then
        lib.notify({ title = 'Police', description = msg, type = 'success' })
    else
        lib.notify({ title = 'Police', description = msg or 'Failed to revoke license.', type = 'error' })
    end
end

local function openSuspectInteractionsMenu()
    if not ensurePoliceOnDuty() then return end
    if not cacheClosestSuspectOrNotify() then return end

    lib.registerContext({
        id = 'qbx_police:policemenu:suspect',
        title = 'Suspect Interactions',
        menu = 'qbx_police:policemenu:main',
        options = {
            {
                title = 'Handcuff / Uncuff Suspect (soft)',
                description = 'Toggle soft cuffs on nearby suspect.',
                icon = 'fa-solid fa-handcuffs',
                onSelect = actionToggleSoftCuff
            },
            {
                title = 'Handcuff / Uncuff Suspect (hard)',
                description = 'Toggle hard cuffs on nearby suspect.',
                icon = 'fa-solid fa-handcuffs',
                onSelect = actionToggleHardCuff
            },
            {
                title = 'Escort Suspect',
                description = 'Toggle escort on/off.',
                icon = 'fa-solid fa-person-walking',
                onSelect = actionToggleEscort
            },
            {
                title = 'GSR Test',
                description = 'Test nearby suspect for gunshot residue.',
                icon = 'fa-solid fa-vial',
                onSelect = actionGsrTest
            },
            {
                title = 'Place In Vehicle',
                description = 'Place suspect into closest vehicle.',
                icon = 'fa-solid fa-car-side',
                onSelect = actionPlaceInVehicle
            },
            {
                title = 'Remove From Vehicle',
                description = 'Remove suspect from vehicle safely.',
                icon = 'fa-solid fa-person-circle-minus',
                onSelect = actionRemoveFromVehicle
            },
            {
                title = 'Issue Weapon License',
                description = 'Grant weapon license to suspect.',
                icon = 'fa-solid fa-gun',
                onSelect = actionIssueWeaponLicense
            },
            {
                title = 'Revoke Weapon License',
                description = 'Revoke weapon license from suspect.',
                icon = 'fa-solid fa-ban',
                onSelect = actionRevokeWeaponLicense
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:main'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:suspect')
end

-- =========================
-- Identification Menus
-- =========================

local function openLicensesMenu(licenses)
    local options = {}

    if type(licenses) ~= 'table' or not next(licenses) then
        options[#options + 1] = {
            title = 'No licenses found',
            description = 'Suspect has no valid licenses.',
            icon = 'fa-solid fa-ban',
            --disabled = true
        }
    else
        for _, lic in ipairs(licenses) do
            options[#options + 1] = {
                title = lic.label,
                description = lic.status,
                icon = lic.icon or 'fa-solid fa-id-card'
            }
        end
    end

    options[#options + 1] = {
        title = 'Go Back',
        icon = 'fa-solid fa-arrow-left',
        menu = 'qbx_police:policemenu:ident'
    }

    lib.registerContext({
        id = 'qbx_police:policemenu:licenses',
        title = 'Licenses',
        options = options
    })

    lib.showContext('qbx_police:policemenu:licenses')
end

-- NEW: Detailed suspect information context menu
local function openDetailedSuspectMenu(identity)
    local options = {}

    -- Full Name
    options[#options + 1] = {
        title = 'Full Name',
        description = identity.fullname or 'Unknown',
        icon = 'fa-solid fa-user',
        disabled = true
    }

    -- Phone Number
    options[#options + 1] = {
        title = 'Phone Number',
        description = identity.phone or 'Unknown',
        icon = 'fa-solid fa-phone',
        disabled = true
    }

    -- Job Details
    options[#options + 1] = {
        title = 'Job Details',
        description = (identity.job or 'Unknown') .. ' - ' .. (identity.position or 'Unknown'),
        icon = 'fa-solid fa-briefcase',
        disabled = true
    }

    -- Gang Details
    options[#options + 1] = {
        title = 'Gang Details',
        description = identity.gang or 'None',
        icon = 'fa-solid fa-users',
        disabled = true
    }

    -- Warrant Status
    local warrantIcon = identity.haswarrant and 'fa-solid fa-exclamation-triangle' or 'fa-solid fa-check'
    options[#options + 1] = {
        title = 'Warrant Status',
        description = identity.warrant or 'No',
        icon = warrantIcon,
        disabled = true
    }

    -- Go Back
    options[#options + 1] = {
        title = 'Go Back',
        icon = 'fa-solid fa-arrow-left',
        menu = 'qbx_police:policemenu:ident'
    }

    lib.registerContext({
        id = 'qbx_police:policemenu:ident:detailed',
        title = 'Suspect Details',
        menu = 'qbx_police:policemenu:ident',
        options = options
    })

    lib.showContext('qbx_police:policemenu:ident:detailed')
end

local function openIdentificationResultsMenu(identity)
    lib.registerContext({
        id = 'qbx_police:policemenu:ident',
        title = 'Identification Results',
        menu = 'qbx_police:policemenu:main',
        options = {
            {
                title = 'Suspect Details',
                description = 'View personal information.',
                icon = 'fa-solid fa-user',
                onSelect = function()
                    openDetailedSuspectMenu(identity)
                end
            },
            {
                title = 'Licenses',
                description = 'View license statuses.',
                icon = 'fa-solid fa-id-card-clip',
                onSelect = function()
                    openLicensesMenu(identity.licenses)
                end
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:main'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:ident')
end

local function checkIdentification()
    if not ensurePoliceOnDuty() then return end

    local targetSrc = getClosestPlayerServerId()
    if not targetSrc then return end

    local identity = lib.callback.await('qbx_police:server:getIdentification', false, targetSrc)
    if not identity then
        lib.notify({ title = 'Police', description = 'Unable to retrieve ID.', type = 'error' })
        return
    end

    openIdentificationResultsMenu(identity)
end

-- =========================
-- Vehicle Menus
-- =========================

-- IMPROVED: Get vehicle details using native functions
local function getVehicleDetails(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then 
        return nil
    end
    
    local plate = getVehiclePlate(vehicle) or 'UNKNOWN'  -- CODE QUALITY FIX #16: Defensive null check
    local model = GetEntityModel(vehicle)
    local modelLabel = GetLabelText(GetDisplayNameFromVehicleModel(model)) or 'Unknown Vehicle'
    
    return {
        entity = vehicle,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        model = model,
        modelLabel = modelLabel
    }
end

local function openVehicleInfoMenu(vehicleInfo)
    -- Owner Context
    lib.registerContext({
        id = 'qbx_police:policemenu:vehinfo:owner',
        title = 'Vehicle Owner',
        menu = 'qbx_police:policemenu:vehinfo',
        options = {
            {
                title = vehicleInfo.owner or 'Unknown',
                description = 'Vehicle Owner Name',
                icon = 'fa-solid fa-user',
                disabled = true
            },
            {
                title = vehicleInfo.citizenid or 'N/A',
                description = 'Citizen ID',
                icon = 'fa-solid fa-id-card',
                disabled = true
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:vehinfo'
            }
        }
    })

    -- Plate Number Context
    lib.registerContext({
        id = 'qbx_police:policemenu:vehinfo:plate',
        title = 'Plate Information',
        menu = 'qbx_police:policemenu:vehinfo',
        options = {
            {
                title = vehicleInfo.plate or 'Unknown',
                description = 'Vehicle Plate Number',
                icon = 'fa-solid fa-barcode',
                disabled = true
            },
            {
                title = vehicleInfo.modelLabel or 'Unknown',
                description = 'Vehicle Model',
                icon = 'fa-solid fa-car',
                disabled = true
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:vehinfo'
            }
        }
    })

    -- Expiration Status Context
    local expirationStatus = vehicleInfo.expiration or 'Unknown'
    local expirationIcon = 'fa-solid fa-calendar-check'
    local expirationColor = 'success'
    
    if expirationStatus:lower():find('expired') or expirationStatus:lower():find('overdue') then
        expirationIcon = 'fa-solid fa-calendar-xmark'
        expirationColor = 'error'
    end

    lib.registerContext({
        id = 'qbx_police:policemenu:vehinfo:expiration',
        title = 'Vehicle Status',
        menu = 'qbx_police:policemenu:vehinfo',
        options = {
            {
                title = expirationStatus,
                description = 'Expiration/Registration Status',
                icon = expirationIcon,
                disabled = true
            },
            {
                title = vehicleInfo.stolen and 'STOLEN' or 'Not Stolen',
                description = 'Theft Status',
                icon = vehicleInfo.stolen and 'fa-solid fa-exclamation-triangle' or 'fa-solid fa-shield',
                disabled = true
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:vehinfo'
            }
        }
    })

    -- Active Penalties Context
    lib.registerContext({
        id = 'qbx_police:policemenu:vehinfo:penalties',
        title = 'Vehicle Penalties',
        menu = 'qbx_police:policemenu:vehinfo',
        options = {
            {
                title = vehicleInfo.flagged and 'YES - Vehicle Flagged' or 'No Active Flags',
                description = 'Law Enforcement Flag Status',
                icon = vehicleInfo.flagged and 'fa-solid fa-flag' or 'fa-solid fa-check',
                disabled = true
            },
            {
                title = vehicleInfo.activePenalties or 'No Penalties',
                description = 'Active Penalties/Fines',
                icon = 'fa-solid fa-gavel',
                disabled = true
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:vehinfo'
            }
        }
    })

    -- Main Vehicle Info Context
    lib.registerContext({
        id = 'qbx_police:policemenu:vehinfo',
        title = 'Vehicle Information',
        menu = 'qbx_police:policemenu:vehicle',
        options = {
            {
                title = 'Owner',
                description = vehicleInfo.owner or 'Unknown',
                icon = 'fa-solid fa-user',
                menu = 'qbx_police:policemenu:vehinfo:owner'
            },
            {
                title = 'Plate No.',
                description = vehicleInfo.plate or 'Unknown',
                icon = 'fa-solid fa-barcode',
                menu = 'qbx_police:policemenu:vehinfo:plate'
            },
            {
                title = 'Expiration Status',
                description = vehicleInfo.expiration or 'Unknown',
                icon = 'fa-solid fa-calendar',
                menu = 'qbx_police:policemenu:vehinfo:expiration'
            },
            {
                title = 'Active Penalties',
                description = vehicleInfo.flagged and 'Vehicle Flagged' or 'No Issues',
                icon = 'fa-solid fa-gavel',
                menu = 'qbx_police:policemenu:vehinfo:penalties'
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:vehicle'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:vehinfo')
end

local function showVehicleInformation()
    if not ensurePoliceOnDuty() then return end

    local vehicle = getClosestVehicleOrNotify()
    if not vehicle then return end

    -- Get vehicle details using QBox functions
    local vehDetails = getVehicleDetails(vehicle)
    if not vehDetails then
        lib.notify({ title = 'Police', description = 'Invalid vehicle.', type = 'error' })
        return
    end

    -- Fetch enhanced owner info from server
    local vehicleInfo = lib.callback.await('qbx_police:server:getVehicleDetails', false, vehDetails.plate)

    if not vehicleInfo then
        vehicleInfo = {
            plate = vehDetails.plate,
            modelLabel = vehDetails.modelLabel,
            owner = 'Unknown',
            flagged = false
        }
    end

    -- Merge vehicle details with server info
    vehicleInfo.modelLabel = vehicleInfo.modelLabel or vehDetails.modelLabel
    
    openVehicleInfoMenu(vehicleInfo)
end

local function lockpickNearbyVehicle()
    if not ensurePoliceOnDuty() then return end

    local vehicle = getClosestVehicleOrNotify()
    if not vehicle then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    local ok, err = lib.callback.await('qbx_police:server:validateLockpickVehicle', false, netId)
    if not ok then
        lib.notify({ title = 'Police', description = err or 'Cannot lockpick this vehicle.', type = 'error' })
        return
    end

    local success = lib.progressCircle({
        duration = 6500,
        position = 'bottom',
        label = 'Attempting lockpick...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, mouse = false },
        anim = { dict = 'missheistfbisetup1', clip = 'unlock_loop_janitor' }
    })

    if not success then
        lib.notify({ title = 'Police', description = 'Cancelled.', type = 'error' })
        return
    end

    local skill = lib.skillCheck({ 'easy', 'medium', 'medium' }, { 'w', 'a', 's', 'd' })
    if not skill then
        lib.notify({ title = 'Police', description = 'Lockpick failed.', type = 'error' })
        return
    end

    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    lib.notify({ title = 'Police', description = 'Vehicle unlocked.', type = 'success' })
end

local function impoundConfirmationDialog()
    if not ensurePoliceOnDuty() then return end

    local vehicle = getClosestVehicleOrNotify()
    if not vehicle then return end

    local input = lib.inputDialog('Impound', {
        { type = 'checkbox', label = 'Full impound (forever)?' },
        {
            type = 'number',
            label = 'Fine amount',
            description = 'If you dont want any fee then just confirm',
            default = 0,
            min = 0,
            max = 1000000  -- CODE QUALITY FIX #15: Add max to prevent absurd values
        }
    })

    if not input then return end

    local fullImpound = input[1] == true
    local fineAmount = tonumber(input[2]) or 0

    -- CODE QUALITY FIX #15: Validate fine amount (check for NaN)
    if fineAmount < 0 or fineAmount ~= fineAmount then
        lib.notify({ title = 'Impound', description = 'Invalid fine amount.', type = 'error' })
        return
    end

    -- Use the existing impound event (which has the progress circle)
    TriggerEvent('police:client:ImpoundVehicle', fullImpound, fineAmount)
end

local function openVehicleMenu()
    lib.registerContext({
        id = 'qbx_police:policemenu:vehicle',
        title = 'Vehicle Interactions',
        menu = 'qbx_police:policemenu:main',
        options = {
            {
                title = 'Vehicle Information',
                description = 'Show plate number and owner.',
                icon = 'fa-solid fa-file-lines',
                onSelect = showVehicleInformation
            },
            {
                title = 'Lockpick Vehicle',
                description = 'Attempt to lockpick nearby vehicle.',
                icon = 'fa-solid fa-lock-open',
                onSelect = lockpickNearbyVehicle
            },
            {
                title = 'Impound Vehicle',
                description = 'Open impound confirmation dialog.',
                icon = 'fa-solid fa-truck-pickup',
                onSelect = impoundConfirmationDialog
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:main'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:vehicle')
end

-- =========================
-- Place Objects Menu
-- =========================

local function safeSpawnObject(key)
    if not ensurePoliceOnDuty() then return end

    -- Reuse existing object placement logic/events in qbx_police
    -- Note: sharedConfig.objects keys are defined in config/shared.lua
    if key == 'spikestrip' then
        TriggerEvent('police:client:SpawnSpikeStrip')
        return
    end

    if not sharedConfig.objects[key] then
        lib.notify({ title = 'Police', description = 'This object is not configured.', type = 'error' })
        return
    end

    local model = sharedConfig.objects[key].model
    if not IsModelInCdimage(model) or not IsModelValid(model) then
        lib.notify({ title = 'Police', description = 'Object model not available.', type = 'error' })
        return
    end

    TriggerEvent('police:client:spawnPObj', key)
end

local function openPlaceObjectsMenu()
    lib.registerContext({
        id = 'qbx_police:policemenu:objects',
        title = 'Place Objects',
        menu = 'qbx_police:policemenu:main',
        options = {
            {
                title = 'Light Traffic Barricade',
                description = 'Place a barricade on the ground.',
                icon = 'fa-solid fa-road-barrier',
                onSelect = function() safeSpawnObject('barrier') end
            },
            {
                title = 'Mobile Barrier',
                description = 'Place a barrier on the ground.',
                icon = 'fa-solid fa-road-barrier',
                onSelect = function() safeSpawnObject('barrier') end
            },
            {
                title = 'Police Barrier Extend',
                description = 'Place an extend barrier on the ground.',
                icon = 'fa-solid fa-road-barrier',
                onSelect = function() safeSpawnObject('barrier') end
            },
            {
                title = 'Traffic Cones',
                description = 'Place traffic cones on the ground.',
                icon = 'fa-solid fa-triangle-exclamation',
                onSelect = function() safeSpawnObject('cone') end
            },
            {
                title = 'Spike Strip',
                description = 'Place a spike strip on the road.',
                icon = 'fa-solid fa-grip-lines',
                onSelect = function() safeSpawnObject('spikestrip') end
            },
            {
                title = 'Police Tape',
                description = 'Place police tape (mapped to barrier).',
                icon = 'fa-solid fa-tape',
                onSelect = function() safeSpawnObject('barrier') end
            },
            {
                title = 'Light Flare',
                description = 'Place a light (worklight) on the ground.',
                icon = 'fa-solid fa-lightbulb',
                onSelect = function() safeSpawnObject('light') end
            },
            {
                title = 'Warning Sign',
                description = 'Place a warning sign on the ground.',
                icon = 'fa-solid fa-sign-hanging',
                onSelect = function() safeSpawnObject('roadsign') end
            },
            {
                title = 'Tent',
                description = 'Place a tent on the ground.',
                icon = 'fa-solid fa-tent',
                onSelect = function() safeSpawnObject('tent') end
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:main'
            }
        }
    })

    lib.showContext('qbx_police:policemenu:objects')
end

-- =========================
-- Jail System Menu
-- =========================

local function actionJailSuspect()
    if not ensurePoliceOnDuty() then return end
    local coords = GetEntityCoords(cache.ped)
    local playerId = lib.getClosestPlayer(coords, 2.0)
    if not playerId then
        lib.notify({ title = 'Police', description = 'No nearby suspect.', type = 'error' })
        return
    end

    local playerName = GetPlayerName(playerId)
    
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
    local dialog = lib.inputDialog('Jail Time', {
        {type = 'number', label = 'Time (months)', min = 0}
    })
    if dialog and dialog[1] > 0 then
        local serverId = GetPlayerServerId(playerId)
        TriggerServerEvent('police:server:JailPlayer', serverId, dialog[1])
    else
        lib.notify({ title = 'Police', description = 'Invalid jail time.', type = 'error' })
    end
end

local function actionUnjailSuspect()
    if not ensurePoliceOnDuty() then return end
    
    -- Get list of jailed players from server
    local jailedPlayers = lib.callback.await('police:server:getJailedPlayers', false)
    
    if not jailedPlayers or not next(jailedPlayers) then
        lib.notify({ title = 'Police', description = 'No jailed players found.', type = 'error' })
        return
    end
    
    -- Create menu options from jailed players list
    local options = {}
    for _, playerData in ipairs(jailedPlayers) do
        options[#options + 1] = {
            title = playerData.name,
            description = 'Jail time: ' .. playerData.jailTime .. ' months',
            icon = 'fa-solid fa-user',
            onSelect = function()
                -- Confirm unjail
                local confirmed = lib.alertDialog({
                    header = 'Unjail Player',
                    content = 'Are you sure you want to unjail ' .. playerData.name .. '?',
                    centered = true,
                    cancel = true,
                    labels = {
                        confirm = 'Unjail',
                        cancel = 'Cancel'
                    }
                })
                
                if confirmed then
                    TriggerServerEvent('police:server:UnjailPlayer', playerData.serverId)
                    lib.notify({ title = 'Police', description = playerData.name .. ' has been released.', type = 'success' })
                end
            end
        }
    end
    
    options[#options + 1] = {
        title = 'Go Back',
        icon = 'fa-solid fa-arrow-left',
        menu = 'qbx_police:policemenu:jail'
    }
    
    lib.registerContext({
        id = 'qbx_police:policemenu:jail:list',
        title = 'Select Player to Unjail',
        menu = 'qbx_police:policemenu:jail',
        options = options
    })
    
    lib.showContext('qbx_police:policemenu:jail:list')
end

local function openJailSystemMenu()
    if not ensurePoliceOnDuty() then return end
    
    lib.registerContext({
        id = 'qbx_police:policemenu:jail',
        title = 'Jail System',
        menu = 'qbx_police:policemenu:main',
        options = {
            {
                title = 'Jail Suspect',
                description = 'Jail a nearby suspect.',
                icon = 'fa-solid fa-lock',
                onSelect = actionJailSuspect
            },
            {
                title = 'Unjail Suspect',
                description = 'Release a jailed suspect.',
                icon = 'fa-solid fa-unlock',
                onSelect = actionUnjailSuspect
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:main'
            }
        }
    })
    
    lib.showContext('qbx_police:policemenu:jail')
end

-- =========================
-- Robbery Control Menu (Requested)
-- =========================

--[[local function openRobberyActionsMenu(robberyType, label, isActive)
    lib.registerContext({
        id = ('qbx_police:policemenu:robberies:%s'):format(robberyType),
        title = label or robberyType,
        menu = 'qbx_police:policemenu:robberies',
        options = {
            {
                title = 'Reset Robbery',
                description = isActive and 'Finish this robbery in progress.' or 'Not in progress - reset state.',
                icon = isActive and 'fa-solid fa-square-check' or 'fa-solid fa-rotate',
                onSelect = function()
                    if not ensurePoliceOnDuty() then return end
                    
                    local confirmMsg = isActive and 'Finish this robbery in progress?' or 'Reset robbery state?'
                    local confirm = lib.alertDialog({
                        header = 'Reset Robbery?',
                        content = confirmMsg,
                        centered = true,
                        cancel = true
                    })
                    if confirm ~= 'confirm' then return end

                    local res = lib.callback.await('dex_robberycreator:server:completeRobberyAsPolice', false, robberyType)
                    if not res or not res.success then
                        lib.notify({ title = 'Police', description = (res and res.message) or 'Unable to reset robbery.', type = 'error' })
                        return
                    end
                    lib.notify({ title = 'Police', description = res.message, type = 'success' })
                    Wait(0)
                    TriggerEvent('qbx_police:client:openRobberyControlMenu')
                end
            },
            {
                title = 'Go Back',
                icon = 'fa-solid fa-arrow-left',
                menu = 'qbx_police:policemenu:robberies'
            }
        }
    })

    lib.showContext(('qbx_police:policemenu:robberies:%s'):format(robberyType))
end

local function openRobberyControlMenu()
    if not ensurePoliceOnDuty() then return end

    local res = lib.callback.await('dex_robberycreator:server:getRobberyControlList', false)
    if not res or not res.success then
        lib.notify({ title = 'Police', description = (res and res.message) or 'Robbery control unavailable (is dex_robberycreator started?)', type = 'error' })
        return
    end

    local options = {}
    for _, r in ipairs(res.robberies or {}) do
        options[#options + 1] = {
            title = r.label or r.type,
            description = r.isActive and 'Status: IN PROGRESS' or 'Status: Not in progress',
            icon = r.isActive and 'fa-solid fa-circle-exclamation' or 'fa-solid fa-circle-info',
            onSelect = function()
                openRobberyActionsMenu(r.type, r.label, r.isActive)
            end
        }
    end

    options[#options + 1] = {
        title = 'Go Back',
        icon = 'fa-solid fa-arrow-left',
        menu = 'qbx_police:policemenu:main'
    }

    lib.registerContext({
        id = 'qbx_police:policemenu:robberies',
        title = 'Robbery Control',
        menu = 'qbx_police:policemenu:main',
        options = options
    })

    lib.showContext('qbx_police:policemenu:robberies')
end

RegisterNetEvent('qbx_police:client:openRobberyControlMenu', openRobberyControlMenu)
]]
-- =========================
-- Main Menu
-- =========================

local function openPoliceMainMenu()
    lib.registerContext({
        id = 'qbx_police:policemenu:main',
        title = 'Police',
        options = {
            -- NEW (Requested): suspect interactions submenu
            {
                title = 'Suspect Interactions',
                description = 'Cuff, escort, GSR, vehicle actions.',
                icon = 'fa-solid fa-user-shield',
                onSelect = openSuspectInteractionsMenu
            },
            {
                title = 'Check Identification',
                description = "Check nearby suspect's I.D.",
                icon = 'fa-solid fa-id-card',
                onSelect = checkIdentification
            },
            {
                title = 'Place Tracker',
                description = 'Place/remove tracker on person or vehicle.',
                icon = 'fa-solid fa-location-dot',
                onSelect = openTrackerMenu
            },
            {
                title = 'Vehicle Interactions',
                description = 'Inspect nearby vehicle.',
                icon = 'fa-solid fa-car',
                onSelect = openVehicleMenu
            },
            {
                title = 'Place Objects',
                description = 'Place police objects on the ground.',
                icon = 'fa-solid fa-road',
                onSelect = openPlaceObjectsMenu
            },
            {
                title = 'Jail System',
                description = 'Jail or unjail suspects.',
                icon = 'fa-solid fa-gavel',
                onSelect = openJailSystemMenu
            },
            {
                title = 'Robbery Control',
                description = 'Enable/disable robberies and reset cooldowns.',
                icon = 'fa-solid fa-stopwatch',
                onSelect = openRobberyControlMenu
            },
            {
                title = 'Fines',
                description = 'Issue a nearby player a fine.',
                icon = 'fa-solid fa-receipt',
                onSelect = function()
                    if not ensurePoliceOnDuty() then return end
                    -- Reuse existing billing logic (lib.inputDialog + server validation)
                    TriggerEvent('police:client:BillPlayer')
                end
            }
        }
    })

    lib.showContext('qbx_police:policemenu:main')
end

-- =========================
-- Command + Keybind (F5)
-- =========================

local function openPoliceMenu()
    if not ensurePoliceOnDuty() then return end
    openPoliceMainMenu()
end

RegisterCommand('pdac', function()
    openPoliceMenu()
end, false)


CreateThread(function()
    exports.ox_target:addGlobalPlayer({
        {
            name = 'police_menu',
            icon = 'fa-solid fa-shield-halved',
            label = 'Police Actions',
            distance = 3.0,

            canInteract = function(entity)
                -- allow kahit nasa sasakyan
                if not ensurePoliceOnDuty() then return false end

                -- OPTIONAL: pwede mo alisin kung ayaw mo ng restriction
                -- return true kahit nasa vehicle
                return true
            end,

            onSelect = function()
                openPoliceMenu()
            end
        }
    })
end)






