local M = {}

local ESX = exports['es_extended']:getSharedObject()
local playerLoaded = false
local playerData = ESX.PlayerData or {}

-- If you use a duty script, enable this convar and ensure your duty script sets LocalPlayer.state.onDuty.
local USE_EXTERNAL_DUTY = GetConvarInt('qbx_police:useExternalDuty', 0) == 1

AddEventHandler('esx:playerLoaded', function(xPlayer)
    playerLoaded = true
    playerData = xPlayer or {}
end)

RegisterNetEvent('esx:setJob', function(job)
    playerData.job = job
end)

-- Support both event names seen in the wild.
AddEventHandler('esx:onPlayerLogout', function()
    playerLoaded = false
    playerData = {}
end)

AddEventHandler('esx:onLogout', function()
    playerLoaded = false
    playerData = {}
end)

function M.isPlayerLoaded()
    if ESX and ESX.PlayerData and ESX.PlayerData.job ~= nil then
        return true
    end
    return playerLoaded == true
end

function M.getJob()
    return (ESX and ESX.PlayerData and ESX.PlayerData.job) or (playerData and playerData.job) or nil
end

function M.isJob(jobNames)
    local job = M.getJob()
    if not job or not job.name then return false end

    if type(jobNames) == 'string' then
        return job.name == jobNames
    end

    if type(jobNames) ~= 'table' then
        return job.name == 'police'
    end

    for i = 1, #jobNames do
        if job.name == jobNames[i] then
            return true
        end
    end

    return false
end

function M.isOnDuty()
    -- ESX default: always on-duty unless you provide duty state.
    if not USE_EXTERNAL_DUTY then return true end

    local state = LocalPlayer and LocalPlayer.state
    if state and state.onDuty ~= nil then
        return state.onDuty == true
    end

    -- If no duty state is present, treat as on-duty.
    return true
end

return M
