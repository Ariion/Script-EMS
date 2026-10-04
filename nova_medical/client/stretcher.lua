-- nova_medical/client/stretcher.lua
-- Système de brancardage & transport patient

local ESX = exports['es_extended']:getSharedObject()

-- État local
local carrying  = nil   -- { ped, serverId } — patient qu'on transporte
local isCarried = false -- ce client est transporté par quelqu'un

-- Offset d'attachement (patient sur le côté de l'ambulancier)
local OFFSET = { x = 0.55, y = 0.30, z = 0.15 }
local ROT    = { x = 5.0,  y = 0.0,  z = 78.0  }

-- ── Fonctions principales ─────────────────────────────────────────────────────

function Nova_PickupPatient(targetPed, targetServerId)
    if carrying then
        lib.notify({ title = 'Transport en cours', description = 'Déposez d\'abord le patient actuel.', type = 'warning', duration = 3000 })
        return
    end

    local ok = lib.progressBar({
        duration     = 3500,
        label        = 'Stabilisation du patient...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = {
            dict = 'amb@medic@standing@kneel@idle_a',
            clip = 'idle_a',
        },
    })
    if not ok then return end

    local myPed   = PlayerPedId()
    local myNetId = NetworkGetNetworkIdFromEntity(myPed)
    local patNetId = NetworkGetNetworkIdFromEntity(targetPed)

    TriggerServerEvent('nova_medical:startCarry', targetServerId, myNetId, patNetId)

    carrying = { ped = targetPed, serverId = targetServerId, netId = patNetId }

    -- Attacher le ped patient à l'ambulancier
    AttachEntityToEntity(
        targetPed, myPed, 0,
        OFFSET.x, OFFSET.y, OFFSET.z,
        ROT.x,    ROT.y,    ROT.z,
        false, false, false, false, 2, true
    )

    lib.notify({
        title       = 'Patient brancard',
        description = 'Approchez un véhicule → Charger | [Backspace] → Déposer',
        type        = 'inform',
        duration    = 5000,
        icon        = 'fas fa-procedures',
    })
end

function Nova_DropPatient()
    if not carrying then return end
    DetachEntity(carrying.ped, true, false)
    TriggerServerEvent('nova_medical:stopCarry', carrying.serverId)
    carrying = nil
    lib.notify({ title = 'Patient déposé', type = 'inform', duration = 2000, icon = 'fas fa-procedures' })
end

function Nova_LoadIntoVehicle(vehicle)
    if not carrying then return end

    -- Chercher le premier siège passager libre
    local seat = -1
    for s = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if IsVehicleSeatFree(vehicle, s) then
            seat = s; break
        end
    end
    if seat == -1 then
        lib.notify({ title = 'Véhicule plein', description = 'Aucune place disponible.', type = 'error', duration = 3000 })
        return
    end

    DetachEntity(carrying.ped, true, false)
    local vehNetId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent('nova_medical:loadPatient', carrying.serverId, vehNetId, seat)

    lib.notify({
        title       = 'Patient chargé',
        description = 'Conduisez à l\'hôpital.',
        type        = 'success',
        duration    = 3000,
        icon        = 'fas fa-ambulance',
    })
    carrying = nil
end

function Nova_UnloadPatient(targetServerId)
    TriggerServerEvent('nova_medical:unloadPatient', targetServerId)
    lib.notify({ title = 'Patient sorti du véhicule', type = 'inform', duration = 2000 })
end

-- ── ox_target ─────────────────────────────────────────────────────────────────

CreateThread(function()
    Wait(2000)

    -- Sur les joueurs : brancarder / sortir du véhicule
    exports['ox_target']:addGlobalPlayer({
        {
            name     = 'nova_medical_carry',
            icon     = 'fas fa-procedures',
            label    = 'Brancarder le patient',
            distance = 2.5,
            canInteract = function(entity)
                local xp = ESX.GetPlayerData()
                if not xp or not xp.job then return false end
                if xp.job.name ~= 'ambulance' then return false end
                if carrying then return false end
                -- Ne pas brancarder quelqu'un debout
                return GetEntityHealth(entity) <= 120
            end,
            onSelect = function(data)
                local pid = NetworkGetPlayerIndexFromPed(data.entity)
                local sid = GetPlayerServerId(pid)
                if sid <= 0 then return end
                Nova_PickupPatient(data.entity, sid)
            end,
        },
        {
            name     = 'nova_medical_unload_veh',
            icon     = 'fas fa-ambulance',
            label    = 'Sortir le patient du véhicule',
            distance = 3.0,
            canInteract = function(entity)
                local xp = ESX.GetPlayerData()
                if not xp or not xp.job then return false end
                if xp.job.name ~= 'ambulance' then return false end
                return IsPedInAnyVehicle(entity, false)
            end,
            onSelect = function(data)
                local pid = NetworkGetPlayerIndexFromPed(data.entity)
                local sid = GetPlayerServerId(pid)
                if sid <= 0 then return end
                Nova_UnloadPatient(sid)
            end,
        },
    })

    -- Sur les véhicules : charger le patient transporté
    exports['ox_target']:addGlobalVehicle({
        {
            name     = 'nova_medical_load_veh',
            icon     = 'fas fa-ambulance',
            label    = 'Charger le patient',
            distance = 3.5,
            canInteract = function()
                return carrying ~= nil
            end,
            onSelect = function(data)
                Nova_LoadIntoVehicle(data.entity)
            end,
        },
    })
end)

-- ── Backspace → déposer ───────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(0)
        if carrying and IsControlJustPressed(0, 194) then
            Nova_DropPatient()
        end
    end
end)

-- ── Évènements reçus par le patient ──────────────────────────────────────────

AddEventHandler('nova_medical:evt_beingPickedUp', function()
    isCarried = true
    FreezeEntityPosition(PlayerPedId(), true)
    lib.notify({
        title       = 'Pris en charge',
        description = 'Vous êtes transporté par un ambulancier.',
        type        = 'inform',
        duration    = 5000,
        icon        = 'fas fa-procedures',
    })
end)

AddEventHandler('nova_medical:evt_beingDropped', function()
    isCarried = false
    FreezeEntityPosition(PlayerPedId(), false)
end)

AddEventHandler('nova_medical:evt_loadedInVehicle', function(vehNetId, seat)
    isCarried = false
    FreezeEntityPosition(PlayerPedId(), false)
    Wait(200)
    local veh = NetworkGetEntityFromNetworkId(vehNetId)
    if veh and DoesEntityExist(veh) then
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, seat)
    end
end)

AddEventHandler('nova_medical:evt_unloadedFromVehicle', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        TaskLeaveVehicle(ped, veh, 0)
    end
    FreezeEntityPosition(ped, false)
    isCarried = false
end)

-- ── Commandes de test ────────────────────────────────────────────────────────

RegisterCommand('deposer', function()
    Nova_DropPatient()
end, false)
