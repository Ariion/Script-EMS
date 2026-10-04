-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Client principal
--  Gestion : sync, debuffs, mort, HUD
-- ═══════════════════════════════════════════════════════════════

local ESX = exports['es_extended']:getSharedObject()

-- ── État local ────────────────────────────────────────────────────
local myMedical    = nil   -- sync depuis serveur
local isEms        = false
local uiOpen       = false
local deathScreen  = false
local lastStandEnd = 0
local painKillEnd  = 0     -- timestamp fin analgésiques
local oxygenEnd    = 0     -- timestamp fin O2

-- Debuffs actifs calculés
local activeDebuffs    = {}
local noDriveNotifEnd  = 0   -- cooldown notification conduite

-- ── Sync serveur → client ─────────────────────────────────────────

RegisterNetEvent('nova_medical:sync', function(data)
    myMedical = data
    isEms     = ESX.GetPlayerData().job and ESX.GetPlayerData().job.name == MedConfig.EmsJob
    computeDebuffs()
end)

AddEventHandler('esx:setJob', function(job)
    isEms = (job.name == MedConfig.EmsJob)
end)

-- ── Calcul des debuffs actifs ─────────────────────────────────────

function computeDebuffs()
    if not myMedical then activeDebuffs = {} return end
    local debuffs = {}
    local now = GetGameTimer()
    local painkilled = (painKillEnd > now)

    for zone, zoneDebuffList in pairs(MedConfig.ZoneDebuffs) do
        local zInjuries = myMedical.injuries[zone] or {}
        -- Sévérité max sur cette zone
        local maxSev = 0
        for _, inj in ipairs(zInjuries) do
            if inj.severity > maxSev then maxSev = inj.severity end
        end

        for _, dDef in ipairs(zoneDebuffList) do
            if maxSev >= dDef.threshold then
                -- Les analgésiques atténuent (pas suppriment) les debuffs non sévères
                if not painkilled or maxSev >= 4 then
                    debuffs[dDef.type] = debuffs[dDef.type] or {}
                    debuffs[dDef.type].active    = true
                    debuffs[dDef.type].intensity = dDef.intensity or 1.0
                    debuffs[dDef.type].chance    = dDef.chance or 100
                    debuffs[dDef.type].factor    = dDef.factor  or 1.0
                end
            end
        end
    end

    activeDebuffs = debuffs
end

-- ── Boucle de debuffs (500 ms) ────────────────────────────────────

CreateThread(function()
    while true do
        Wait(500)
        if not myMedical or myMedical.state == 'dead' then goto continue end

        local ped  = PlayerPedId()
        local now  = GetGameTimer()

        -- Mouvement réduit + boiterie
        if activeDebuffs.limp then
            -- Boiterie : on ralentit ET on applique un clipset blessé
            SetPedMoveRateOverride(ped, activeDebuffs.moveSlow and (activeDebuffs.moveSlow.factor or 0.85) or 0.85)
            local clipset = 'move_m@injured'
            if not HasClipSetLoaded(clipset) then RequestClipSet(clipset) end
            if HasClipSetLoaded(clipset) then
                SetPedMovementClipset(ped, clipset, 1.0, true)
            end
        elseif activeDebuffs.moveSlow then
            local factor = activeDebuffs.moveSlow.factor or 0.85
            SetPedMoveRateOverride(ped, factor)
            ResetPedMovementClipset(ped, 0.0)
        else
            SetPedMoveRateOverride(ped, 1.0)
            ResetPedMovementClipset(ped, 0.0)
        end

        -- Interdiction de conduire si jambe critique
        if activeDebuffs.noDrive and IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                TaskLeaveVehicle(ped, veh, 0)
                if now > noDriveNotifEnd then
                    noDriveNotifEnd = now + 8000
                    lib.notify({
                        title       = '⚠️ Impossible de conduire',
                        description = 'Vos blessures vous empêchent de conduire.',
                        type        = 'error',
                        duration    = 4000,
                    })
                end
            end
        end

        -- Pas de sprint
        if activeDebuffs.noSprint then
            DisableControlAction(0, 21, true)  -- Sprint
        end

        -- Pas de saut
        if activeDebuffs.noJump then
            DisableControlAction(0, 22, true)  -- Jump
        end

        -- Tremblement de caméra (permanent selon sévérité)
        if activeDebuffs.cameraShake then
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', activeDebuffs.cameraShake.intensity or 0.1)
        end

        -- Tremblement de visée
        if activeDebuffs.aimShake and IsPedArmed(ped, 6) then
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', activeDebuffs.aimShake.intensity or 0.1)
        end

        -- Pas de tir
        if activeDebuffs.noShoot then
            DisableControlAction(0, 24, true)   -- Attack
            DisableControlAction(0, 25, true)   -- Aim
        end

        -- Ragdoll aléatoire
        if activeDebuffs.ragdoll then
            if math.random(1, 100) <= (activeDebuffs.ragdoll.chance or 10) then
                SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
            end
        end

        -- Stamina drain (ResetPlayerStamina n'existe pas en setter, on use sprint disabled)
        if activeDebuffs.staminaDrain then
            DisableControlAction(0, 21, true)  -- empêche sprint temporairement
        end

        ::continue::
    end
end)

-- ── Boucle effets visuels (1 s) ───────────────────────────────────

CreateThread(function()
    while true do
        Wait(1000)
        if not myMedical or myMedical.state == 'dead' then goto continue end

        -- Flou vision
        if activeDebuffs.visionBlur then
            StartScreenEffect('DeathFailMPIn', 0, true)
        else
            StopScreenEffect('DeathFailMPIn')
        end

        -- Effet ivre
        if activeDebuffs.drunk then
            StartScreenEffect('Drunk', 0, true)
        else
            StopScreenEffect('Drunk')
        end

        ::continue::
    end
end)

-- ── Saignement ───────────────────────────────────────────────────

RegisterNetEvent('nova_medical:bleedTick', function()
    if not myMedical then return end
    local ped = PlayerPedId()
    local hp  = GetEntityHealth(ped)
    if hp > 100 then
        SetEntityHealth(ped, hp - MedConfig.Death.bleedDamage)
        -- Flash sang à l'écran
        StartScreenEffect('KilledByUnknown', 600, false)
    end
end)

-- ── Last Stand ───────────────────────────────────────────────────

RegisterNetEvent('nova_medical:enterLastStand', function(duration)
    if not myMedical then return end
    lastStandEnd = GetGameTimer() + (duration * 1000)
    myMedical.state = 'laststand'

    lib.notify({
        title       = '⚠️ ÉTAT CRITIQUE',
        description = 'Vous êtes à terre. Restez en vie !',
        type        = 'error',
        duration    = 6000,
    })

    -- Permettre de ramper
    local ped = PlayerPedId()
    SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false)

    -- Afficher l'UI de dernière chance
    SendNUIMessage({ action = 'lastStand', duration = duration })
    SetNuiFocus(false, false)
end)

-- ── Mort définitive ───────────────────────────────────────────────

RegisterNetEvent('nova_medical:enterDead', function()
    myMedical.state = 'dead'
    deathScreen     = true

    -- Coucher le ped
    local ped = PlayerPedId()
    SetEntityInvincible(ped, true)
    SetPedToRagdoll(ped, -1, -1, 0, false, false, false)

    -- Ouvrir UI mort
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showDeath', respawnDelay = MedConfig.Death.respawnDelay })
end)

RegisterNetEvent('nova_medical:revived', function()
    myMedical.state = 'injured'
    deathScreen     = false
    lastStandEnd    = 0

    -- Effacer les effets visuels
    StopAllScreenEffects()
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    ClearPedTasks(ped)

    SendNUIMessage({ action = 'hideUI' })
    SetNuiFocus(false, false)

    lib.notify({
        title       = '💉 Réanimation',
        description = 'Vous avez été réanimé(e).',
        type        = 'success',
        duration    = 5000,
    })
end)

RegisterNetEvent('nova_medical:doRespawn', function()
    -- Respawn à l'hôpital
    myMedical = nil
    deathScreen = false
    StopAllScreenEffects()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })

    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetEntityHealth(ped, 200)
    -- Spawn à Pillbox Hill (hôpital de Los Santos)
    local spawnPos = vector3(295.0, -1446.0, 29.9)
    SetEntityCoords(ped, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
    SetEntityHeading(ped, 180.0)
    ClearPedTasks(ped)

    lib.notify({
        title       = '🏥 Hôpital',
        description = 'Vous êtes pris en charge à l\'hôpital.',
        type        = 'inform',
        duration    = 5000,
    })
end)

-- ── NUI Callbacks ─────────────────────────────────────────────────

RegisterNUICallback('requestRespawn', function(_, cb)
    cb('ok')
    TriggerServerEvent('nova_medical:respawn')
end)

RegisterNUICallback('closeUI', function(_, cb)
    cb('ok')
    uiOpen = false
    SetNuiFocus(false, false)
end)

RegisterNUICallback('sendDistress', function(_, cb)
    cb('ok')
    -- Envoyer signal à l'EMS via dispatch
    TriggerServerEvent('nova_medical:distressSignal')
end)

-- ── Signal de détresse ────────────────────────────────────────────

RegisterNetEvent('nova_medical:distressSignal', function(src, patientName, coords)
    if not isEms then return end
    lib.notify({
        title       = '🚨 Signal de détresse',
        description = patientName .. ' a besoin d\'aide !',
        type        = 'error',
        duration    = 8000,
    })
    -- Créer un blip temporaire
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(patientName .. ' — URGENCE')
    EndTextCommandSetBlipName(blip)
    Wait(120000)
    RemoveBlip(blip)
end)

-- ── Notification côté client ──────────────────────────────────────

RegisterNetEvent('nova_medical:notify', function(msg, ntype)
    lib.notify({ description = msg, type = ntype or 'inform', duration = 4000 })
end)

-- ── ESC / Fermeture UI ────────────────────────────────────────────

-- Commande d'urgence si l'UI bloque (/closeui)
RegisterCommand('closeui', function()
    uiOpen      = false
    deathScreen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })
    lib.notify({ description = 'UI fermée.', type = 'inform', duration = 2000 })
end, false)

-- Détection ESC côté Lua (IsDisabledControl fonctionne même avec NuiFocus actif)
CreateThread(function()
    while true do
        Wait(0)
        if uiOpen and not deathScreen then
            if IsControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 200) then
                uiOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'hideUI' })
            end
        end
    end
end)

-- ── HUD — indicateur blessures ────────────────────────────────────

local hudInjuries = 0
local hudBleeding = false

CreateThread(function()
    while true do
        Wait(2000)
        if myMedical then
            local count = 0
            for _, zInj in pairs(myMedical.injuries) do
                count = count + #zInj
            end
            hudInjuries = count
            hudBleeding = myMedical.bleeding
        else
            hudInjuries = 0
            hudBleeding = false
        end
    end
end)

CreateThread(function()
    while true do
        if hudInjuries > 0 then
            Wait(0)
            local txt = '[+] ' .. hudInjuries .. ' blessure' .. (hudInjuries > 1 and 's' or '')
            if hudBleeding then txt = txt .. '  |  ⚡ SAIGNEMENT' end
            local r, g, b = 56, 189, 248
            if hudBleeding or (myMedical and myMedical.state == 'laststand') then
                r, g, b = 239, 68, 68
            elseif hudInjuries >= 4 then
                r, g, b = 245, 158, 11
            end
            SetTextFont(4)
            SetTextScale(0.26, 0.26)
            SetTextColour(r, g, b, 220)
            SetTextDropShadow()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(txt)
            EndTextCommandDisplayText(0.01, 0.96)
        else
            Wait(500)
        end
    end
end)

-- ── Ouverture menu médical (propre fiche) ─────────────────────────

RegisterCommand('medical', function()
    if uiOpen then return end
    if not myMedical then
        lib.notify({ description = 'Données médicales non disponibles.', type = 'error' })
        return
    end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action    = 'openSelf',
        medical   = myMedical,
        isEms     = isEms,
        playerName= GetPlayerName(PlayerId()),
    })
end, false)

-- Exporter l'état local pour examination.lua et treatment.lua
function GetMyMedical() return myMedical end
function GetIsEms()    return isEms end
function SetUiOpen(v)  uiOpen = v end
function SetPainKill(duration)
    painKillEnd = GetGameTimer() + (duration or 30000)
    computeDebuffs()
end
function SetOxygenBoost(duration)
    oxygenEnd = GetGameTimer() + (duration or 30000)
end
