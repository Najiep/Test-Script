ESX = exports['es_extended']:getSharedObject()

local function Notify(src, msg)
    TriggerClientEvent('esx:showNotification', src, msg)
end

local function IsLeoAndOnDuty(xPlayer, minGrade)
    if not xPlayer then return false end
    if xPlayer.job.name ~= 'police' then return false end
    if minGrade and xPlayer.job.grade < minGrade then return false end
    return true
end

local function checkLeoAndOnDuty(xPlayer, minGrade)
    if IsLeoAndOnDuty(xPlayer, minGrade) then return true end
    Notify(xPlayer.source, locale('error.on_duty_police_only'))
    return false
end

local function dnaHash(s)
    return string.gsub(s, '.', function(c)
        return string.format('%02x', string.byte(c))
    end)
end

RegisterCommand('spikestrip', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('police:client:SpawnSpikeStrip', source)
end)

RegisterCommand('grantlicense', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer, config.licenseRank) then
        return Notify(source, locale('error.error_rank_license'))
    end

    local targetId = tonumber(args[1])
    local license = args[2]
    if not config.validLicenses[license] then
        return Notify(source, locale('info.license_type'))
    end

    local target = ESX.GetPlayerFromId(targetId)
    if not target then return end

    local licences = target.getMeta('licences') or {}
    if licences[license] then
        return Notify(source, locale('error.license_already'))
    end

    licences[license] = true
    target.setMeta('licences', licences)

    Notify(targetId, locale('success.granted_license'))
    Notify(source, locale('success.grant_license'))
end)

RegisterCommand('revokelicense', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer, config.licenseRank) then
        return Notify(source, locale('error.rank_revoke'))
    end

    local target = ESX.GetPlayerFromId(tonumber(args[1]))
    local license = args[2]
    if not target or not config.validLicenses[license] then
        return Notify(source, locale('error.error_license'))
    end

    local licences = target.getMeta('licences') or {}
    if not licences[license] then
        return Notify(source, locale('error.error_license'))
    end

    licences[license] = false
    target.setMeta('licences', licences)

    Notify(target.source, locale('error.revoked_license'))
    Notify(source, locale('success.revoke_license'))
end)

RegisterCommand('pobject', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end

    local type = (args[1] or ''):lower()
    if type == 'delete' then
        TriggerClientEvent('police:client:deleteObject', source)
    elseif sharedConfig.objects[type] then
        TriggerClientEvent('police:client:spawnPObj', source, type)
    end
end)

RegisterCommand('cuff', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('police:client:CuffPlayer', source)
end)

RegisterCommand('escort', function(source)
    TriggerClientEvent('police:client:EscortPlayer', source)
end)

RegisterCommand('sc', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('police:client:CuffPlayerSoft', source)
end)

RegisterCommand('jail', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('police:client:JailPlayer', source)
end)

RegisterCommand('unjail', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('prison:client:UnjailPerson', tonumber(args[1]))
end)

RegisterCommand('impound', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('police:client:ImpoundVehicle', source, true)
end)

RegisterCommand('depot', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end
    TriggerClientEvent('police:client:ImpoundVehicle', source, false, tonumber(args[1]))
end)

RegisterCommand('paytow', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not checkLeoAndOnDuty(xPlayer) then return end

    local target = ESX.GetPlayerFromId(tonumber(args[1]))
    if not target or not config.towJobs[target.job.name] then
        return Notify(source, locale('error.not_towdriver'))
    end

    target.addAccountMoney('bank', config.towPay)
    Notify(target.source, locale('success.tow_paid'))
    Notify(source, locale('info.tow_driver_paid'))
end)

RegisterCommand('paylawyer', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer.job.name ~= 'police' and xPlayer.job.name ~= 'judge' then
        return Notify(source, locale('error.on_duty_police_only'))
    end

    local target = ESX.GetPlayerFromId(tonumber(args[1]))
    if not target or not config.lawyerJobs[target.job.name] then
        return Notify(source, locale('error.not_lawyer'))
    end

    target.addAccountMoney('bank', config.lawyerPay)
    Notify(target.source, locale('success.tow_paid'))
    Notify(source, locale('info.paid_lawyer'))
end)

RegisterCommand('takedna', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    local target = ESX.GetPlayerFromId(tonumber(args[1]))
    if not checkLeoAndOnDuty(xPlayer) or not target then return end

    if xPlayer.getInventoryItem('empty_evidence_bag').count < 1 then
        return Notify(source, locale('error.have_evidence_bag'))
    end

    xPlayer.removeInventoryItem('empty_evidence_bag', 1)
    xPlayer.addInventoryItem('filled_evidence_bag', 1, {
        label = locale('info.dna_sample'),
        dnalabel = dnaHash(target.identifier),
        description = dnaHash(target.identifier)
    })
end)