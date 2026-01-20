local lastShotAt = 0
local SHOT_THROTTLE_MS = 1000
local isLoggedIn = LocalPlayer.state.isLoggedIn == true

local function getLocalBagName()
    local serverId = cache and cache.serverId or GetPlayerServerId(cache.playerId)
    return ('player:%s'):format(serverId)
end

AddStateBagChangeHandler('isLoggedIn', nil, function(bagName, _, value)
    if bagName ~= getLocalBagName() then return end
    isLoggedIn = value == true
    if not isLoggedIn then
        lastShotAt = 0
    end
end)

AddStateBagChangeHandler('hasGSR', nil, function(bagName, _, value)
    if bagName ~= getLocalBagName() then return end
    LocalPlayer.state.hasGSR = value == true
end)

CreateThread(function()
    while true do
        Wait(100)  -- More responsive loop
        
        if not isLoggedIn then
            lastShotAt = 0
            goto continue
        end

        if not cache.ped or cache.ped == 0 then goto continue end

        if IsPedShooting(cache.ped) then
            local now = GetGameTimer()
            if now - lastShotAt > SHOT_THROTTLE_MS then
                lastShotAt = now
                LocalPlayer.state:set('hasGSR', true, true)
                TriggerServerEvent('qbx_police:server:addGSR', cache.weapon)
            end
        end

        ::continue::
    end
end)
