-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Soins & Utilisation des items
-- ═══════════════════════════════════════════════════════════════

local ESX = exports['es_extended']:getSharedObject()

-- ── Menu de soin sur un patient ───────────────────────────────────

function OpenTreatMenu(targetSrc)
    local xp = ESX.GetPlayerData()
    local options = {}

    for itemName, itemDef in pairs(MedConfig.HealingItems) do
        -- Vérifier que le joueur possède l'item
        local hasItem = false
        local inv = xp.inventory or {}
        for _, slot in ipairs(inv) do
            if slot.name == itemName and (slot.count or slot.amount or 0) > 0 then
                hasItem = true
                break
            end
        end

        if hasItem then
            -- Vérifier restriction EMS
            if not itemDef.emsOnly or GetIsEms() then
                table.insert(options, {
                    title       = itemDef.label,
                    description = 'Durée : ' .. math.floor(itemDef.duration / 1000) .. 's',
                    icon        = 'fas fa-syringe',
                    onSelect    = function()
                        UseItemOnPatient(targetSrc, itemName, itemDef)
                    end,
                })
            end
        end
    end

    if #options == 0 then
        lib.notify({ description = 'Aucun item de soin disponible.', type = 'error', duration = 3000 })
        return
    end

    table.insert(options, { title = '❌ Annuler', icon = 'fas fa-times' })

    lib.registerContext({
        id      = 'nova_treat_menu',
        title   = '🩹 Soigner le patient',
        options = options,
    })
    lib.showContext('nova_treat_menu')
end

function UseItemOnPatient(targetSrc, itemName, itemDef)
    -- Vérifier distance
    local myPed      = PlayerPedId()
    local targetPed  = GetPlayerPed(GetPlayerFromServerId(targetSrc))
    if targetPed and targetPed ~= 0 then
        local dist = #(GetEntityCoords(myPed) - GetEntityCoords(targetPed))
        if dist > 5.0 then
            lib.notify({ description = 'Patient trop loin.', type = 'error', duration = 2000 })
            return
        end
    end

    -- Orienter vers le patient
    if targetPed and targetPed ~= 0 then
        local tc = GetEntityCoords(targetPed)
        TaskTurnPedToFaceCoord(myPed, tc.x, tc.y, tc.z, 1000)
    end

    local ok = lib.progressBar({
        duration     = itemDef.duration,
        label        = '🩹 ' .. itemDef.label,
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = itemDef.anim.dict, clip = itemDef.anim.clip, flag = 49 },
    })

    if not ok then
        lib.notify({ description = 'Soin annulé.', type = 'warning', duration = 2000 })
        return
    end

    -- Envoyer au serveur
    TriggerServerEvent('nova_medical:heal', targetSrc, itemName, nil)
    lib.notify({ description = itemDef.label .. ' utilisé(e).', type = 'success', duration = 3000 })
end

-- ── Utilisation sur soi-même (via inventaire ESX) ─────────────────

local function useItemOnSelf(itemName)
    local itemDef = MedConfig.HealingItems[itemName]
    if not itemDef then return end

    local myMed = GetMyMedical()
    if not myMed then
        lib.notify({ description = 'Erreur données médicales.', type = 'error' })
        return
    end

    if itemDef.emsOnly and not GetIsEms() then
        lib.notify({ description = 'Réservé au personnel EMS.', type = 'error', duration = 3000 })
        return
    end

    -- Réanimation uniquement par EMS
    if itemDef.revive then
        lib.notify({ description = 'Cet item ne peut pas être utilisé sur soi-même.', type = 'error' })
        return
    end

    -- Barre de progression
    local ok = lib.progressBar({
        duration     = itemDef.duration,
        label        = '💊 ' .. itemDef.label,
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = itemDef.anim.dict, clip = itemDef.anim.clip, flag = 49 },
    })

    if not ok then
        lib.notify({ description = 'Utilisation annulée.', type = 'warning', duration = 2000 })
        return
    end

    -- Envoyer au serveur (targetSrc = nil = soi-même)
    TriggerServerEvent('nova_medical:heal', nil, itemName, nil)

    -- Effets immédiats côté client
    if itemDef.painKill then
        SetPainKill(30000)
        lib.notify({ description = 'Douleur réduite pendant 30 secondes.', type = 'inform', duration = 3000 })
    end
    if itemDef.oxygen then
        SetOxygenBoost(30000)
        lib.notify({ description = 'Saturation en O₂ améliorée.', type = 'inform', duration = 3000 })
    end
    if itemDef.revive then
        -- Géré côté serveur
    end
end

-- ── Enregistrement des items utilisables ─────────────────────────
-- RegisterUsableItem est SERVER-SIDE dans ESX Legacy.
-- Le serveur (server/main.lua) enregistre les items et déclenche :
-- TriggerClientEvent('nova_medical:useItemSelf', source, itemName)

RegisterNetEvent('nova_medical:useItemSelf', function(itemName)
    useItemOnSelf(itemName)
end)

-- ── Détection dégâts armes → blessures ───────────────────────────

-- Surveille les dégâts reçus et les convertit en blessures
local lastDamageTime = 0

CreateThread(function()
    while true do
        Wait(200)
        local ped = PlayerPedId()
        if IsPedInMeleeCombat(ped) or IsPedBeingStunned(ped, 0) then goto continue end

        if HasEntityBeenDamagedByAnyPed(ped) or HasEntityBeenDamagedByAnyVehicle(ped) then
            local now = GetGameTimer()
            if (now - lastDamageTime) < 1000 then goto continue end
            lastDamageTime = now

            -- Détecter la dernière arme utilisée contre nous
            local damageWeapon, damageWeaponDamager = GetPedLastDamageWeapon(ped)
            if damageWeapon == 0 then goto continue end

            -- Trouver le type de blessure
            local weaponName = nil
            for wname, _ in pairs(MedConfig.WeaponInjuryMap) do
                if GetHashKey(wname) == damageWeapon then
                    weaponName = wname
                    break
                end
            end

            local injuryType = MedConfig.WeaponInjuryMap[weaponName] or 'blunt'

            -- Trouver la zone touchée via l'os
            local boneHit = GetPedBoneIndex(ped, 31086) -- défaut : tête
            -- Tenter de récupérer l'os réel
            for boneId, zone in pairs(MedConfig.BoneZoneMap) do
                if IsPedInjured(ped) then
                    boneHit = boneId
                    break
                end
            end

            -- Zone aléatoire pondérée si pas de détection précise
            local zones = { 'head', 'torso', 'torso', 'torso', 'leftArm', 'rightArm', 'leftLeg', 'rightLeg' }
            local zone = zones[math.random(1, #zones)]

            -- Sévérité selon santé perdue
            local hp = GetEntityHealth(ped)
            local sev = 1
            if hp < 150 then sev = 3
            elseif hp < 180 then sev = 2 end

            ClearEntityLastDamageEntity(ped)
            TriggerServerEvent('nova_medical:addInjury', zone, injuryType, sev)
        end

        ::continue::
    end
end)

-- ── Menu contextuel sur joueur à terre (Last Stand) ───────────────

RegisterNetEvent('nova_medical:showRevivePrompt', function()
    if GetIsEms() then
        lib.notify({
            title       = '🚑 Patient à terre',
            description = 'Un patient a besoin de soins urgents.',
            type        = 'warning',
            duration    = 5000,
        })
    end
end)

-- ── Massage cardiaque (CPR) — sans item ───────────────────────────

function DoCPR(targetSrc)
    local myPed    = PlayerPedId()
    local targetPid = GetPlayerFromServerId(targetSrc)
    local targetPed = targetPid >= 0 and GetPlayerPed(targetPid) or nil

    -- Vérification distance
    if targetPed and targetPed ~= 0 then
        local dist = #(GetEntityCoords(myPed) - GetEntityCoords(targetPed))
        if dist > MedConfig.Death.reviveDistance then
            lib.notify({ description = 'Patient trop loin.', type = 'error', duration = 2000 })
            return
        end
        -- S'orienter vers le patient
        local tc = GetEntityCoords(targetPed)
        TaskTurnPedToFaceCoord(myPed, tc.x, tc.y, tc.z, 800)
        Wait(900)
    end

    local ok = lib.progressBar({
        duration     = 16000,
        label        = '🫀 Massage cardiaque en cours...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 49 },
    })

    if not ok then
        lib.notify({ description = 'CPR interrompu.', type = 'warning', duration = 2000 })
        return
    end

    TriggerServerEvent('nova_medical:cpr', targetSrc)
end

-- ── Défibrillateur — avec item ────────────────────────────────────

function UseDefibrillator(targetSrc)
    local myPed     = PlayerPedId()
    local targetPid = GetPlayerFromServerId(targetSrc)
    local targetPed = targetPid >= 0 and GetPlayerPed(targetPid) or nil

    -- Vérification item
    local xp = ESX.GetPlayerData()
    local hasDefib = false
    for _, slot in ipairs(xp.inventory or {}) do
        if slot.name == 'defibrillateur' and (slot.count or slot.amount or 0) > 0 then
            hasDefib = true; break
        end
    end
    if not hasDefib then
        lib.notify({ description = 'Vous n\'avez pas de défibrillateur.', type = 'error', duration = 3000 })
        return
    end

    -- Vérification distance
    if targetPed and targetPed ~= 0 then
        local dist = #(GetEntityCoords(myPed) - GetEntityCoords(targetPed))
        if dist > MedConfig.Death.reviveDistance then
            lib.notify({ description = 'Patient trop loin.', type = 'error', duration = 2000 })
            return
        end
        local tc = GetEntityCoords(targetPed)
        TaskTurnPedToFaceCoord(myPed, tc.x, tc.y, tc.z, 800)
        Wait(900)
    end

    local ok = lib.progressBar({
        duration     = 9000,
        label        = '⚡ Défibrillation en cours...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 49 },
    })

    if not ok then
        lib.notify({ description = 'Défibrillation annulée.', type = 'warning', duration = 2000 })
        return
    end

    -- Utilise le flow heal existant (retire l'item + revive côté serveur)
    TriggerServerEvent('nova_medical:heal', targetSrc, 'defibrillateur', nil)
end
