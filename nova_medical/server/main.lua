-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Server
-- ═══════════════════════════════════════════════════════════════

local ESX = exports['es_extended']:getSharedObject()

-- ── Stockage en mémoire ───────────────────────────────────────────
-- PlayerMedical[src] = {
--   state    = 'conscious'|'laststand'|'dead',
--   injuries = { head={}, torso={}, leftArm={}, rightArm={}, leftLeg={}, rightLeg={} },
--   diseases = { [diseaseId] = { severity=float } },
--   bleeding = bool,
--   lastStandTimer = int (timestamp),
-- }

local PlayerMedical = {}
MonitoredPatients   = {}  -- global: lu par le thread monitoring ci-dessous

-- ── Helpers ───────────────────────────────────────────────────────

local function defaultMedical()
    return {
        state    = 'conscious',
        injuries = { head={}, torso={}, leftArm={}, rightArm={}, leftLeg={}, rightLeg={} },
        diseases = {},
        bleeding = false,
        lastStandTimer = 0,
    }
end

local function getMedical(src)
    if not PlayerMedical[src] then
        PlayerMedical[src] = defaultMedical()
    end
    return PlayerMedical[src]
end

local function syncToClient(src)
    TriggerClientEvent('nova_medical:sync', src, getMedical(src))
end

local function syncToNearbyEms(src)
    local xPatient = ESX.GetPlayerFromId(src)
    if not xPatient then return end
    for _, pid in ipairs(ESX.GetPlayers()) do
        local xp = ESX.GetPlayerFromId(pid)
        if xp and xp.getJob().name == MedConfig.EmsJob then
            TriggerClientEvent('nova_medical:patientUpdate', pid, src, xPatient.getName(), getMedical(src))
        end
    end
end

-- ── Base de données ───────────────────────────────────────────────

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `nova_medical_data` (
            `identifier`  VARCHAR(60)  NOT NULL,
            `injuries`    LONGTEXT     DEFAULT NULL,
            `diseases`    LONGTEXT     DEFAULT NULL,
            `updated_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `nova_hospital_records` (
            `id`           INT AUTO_INCREMENT PRIMARY KEY,
            `patient_id`   VARCHAR(60)  NOT NULL DEFAULT '',
            `patient_name` VARCHAR(100) NOT NULL DEFAULT '',
            `ems_id`       VARCHAR(60)  NOT NULL DEFAULT '',
            `ems_name`     VARCHAR(100) NOT NULL DEFAULT '',
            `diagnosis`    TEXT         DEFAULT NULL,
            `exams`        LONGTEXT     DEFAULT NULL,
            `notes`        TEXT         DEFAULT NULL,
            `severity`     VARCHAR(30)  DEFAULT 'Stable',
            `cost`         INT          DEFAULT 0,
            `treated_at`   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

local function loadFromDB(identifier, cb)
    MySQL.query('SELECT injuries, diseases FROM nova_medical_data WHERE identifier = ?', { identifier }, function(res)
        if res and res[1] then
            local injuries = json.decode(res[1].injuries or '{}') or {}
            local diseases = json.decode(res[1].diseases or '{}') or {}
            cb(injuries, diseases)
        else
            cb(nil, nil)
        end
    end)
end

local function saveToDB(src)
    local xp  = ESX.GetPlayerFromId(src)
    if not xp then return end
    local med = getMedical(src)
    MySQL.insert(
        'INSERT INTO nova_medical_data (identifier, injuries, diseases) VALUES (?,?,?) ON DUPLICATE KEY UPDATE injuries=VALUES(injuries), diseases=VALUES(diseases)',
        { xp.identifier, json.encode(med.injuries), json.encode(med.diseases) }
    )
end

-- ── Items utilisables (ESX Legacy = server-side) ─────────────────

MySQL.ready(function()
    for itemName in pairs(MedConfig.HealingItems) do
        ESX.RegisterUsableItem(itemName, function(source)
            TriggerClientEvent('nova_medical:useItemSelf', source, itemName)
        end)
    end
end)

-- ── Connexion / Déconnexion ───────────────────────────────────────

AddEventHandler('esx:playerLoaded', function(src)
    local xp = ESX.GetPlayerFromId(src)
    if not xp then return end
    PlayerMedical[src] = defaultMedical()
    loadFromDB(xp.identifier, function(injuries, diseases)
        if injuries then PlayerMedical[src].injuries = injuries end
        if diseases then PlayerMedical[src].diseases = diseases end
        syncToClient(src)
    end)
end)

AddEventHandler('esx:playerDropped', function(src)
    if PlayerMedical[src] then
        saveToDB(src)
        PlayerMedical[src] = nil
    end
    -- Si ce joueur était monitoré, stopper le monitoring pour tous les EMS
    if MonitoredPatients[src] then
        MonitoredPatients[src] = nil
        for _, pid in ipairs(ESX.GetPlayers()) do
            local xEms = ESX.GetPlayerFromId(pid)
            if xEms and xEms.getJob().name == MedConfig.EmsJob then
                TriggerClientEvent('nova_medical:monitoringStop', pid, src)
            end
        end
    end
end)

-- Sauvegarde auto toutes les 5 minutes
CreateThread(function()
    while true do
        Wait(300000)
        for src in pairs(PlayerMedical) do
            saveToDB(src)
        end
    end
end)

-- ── Blessures ─────────────────────────────────────────────────────

RegisterNetEvent('nova_medical:addInjury', function(zone, injuryType, severity)
    local src = source
    local med = getMedical(src)
    if med.state == 'dead' then return end

    zone     = zone or 'torso'
    severity = math.max(1, math.min(5, severity or 1))

    local def = MedConfig.InjuryTypes[injuryType]
    if not def then return end

    -- Fusionner avec une blessure existante du même type sur la même zone
    local existing = nil
    for _, inj in ipairs(med.injuries[zone] or {}) do
        if inj.type == injuryType then
            existing = inj
            break
        end
    end

    if existing then
        existing.severity = math.min(5, existing.severity + math.max(1, math.floor(severity * 0.5)))
    else
        table.insert(med.injuries[zone], {
            type     = injuryType,
            severity = severity,
            ts       = os.time(),
        })
    end

    -- Saignement
    if def.bleed then med.bleeding = true end

    -- Calculer état global
    local totalInjuries = 0
    local maxSev = 0
    for _, zInjuries in pairs(med.injuries) do
        for _, inj in ipairs(zInjuries) do
            totalInjuries = totalInjuries + 1
            if inj.severity > maxSev then maxSev = inj.severity end
        end
    end

    if maxSev >= 5 or totalInjuries >= 8 then
        if med.state == 'conscious' or med.state == 'injured' then
            med.state = 'laststand'
            med.lastStandTimer = os.time() + MedConfig.Death.lastStandTime
            TriggerClientEvent('nova_medical:enterLastStand', src, MedConfig.Death.lastStandTime)
            -- Auto-dispatch vers les EMS
            local xpSrc = ESX.GetPlayerFromId(src)
            if xpSrc then
                local pedCoords = GetEntityCoords(GetPlayerPed(src))
                pcall(function()
                    exports['nova_dispatch']:addCall({
                        job     = MedConfig.EmsJob,
                        title   = '🚑 Patient en détresse',
                        message = xpSrc.getName() .. ' est en état critique — réanimation requise.',
                        coords  = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z },
                        blip    = { sprite = 153, colour = 1, scale = 0.9 },
                    })
                end)
            end
        end
    elseif maxSev >= 3 or totalInjuries >= 4 then
        if med.state == 'conscious' then med.state = 'injured' end
    end

    syncToClient(src)
    syncToNearbyEms(src)
end)

-- Mort définitive
RegisterNetEvent('nova_medical:die', function()
    local src = source
    local med = getMedical(src)
    med.state   = 'dead'
    med.bleeding = false
    syncToClient(src)
    syncToNearbyEms(src)
    saveToDB(src)
end)

-- ── Soins ─────────────────────────────────────────────────────────

RegisterNetEvent('nova_medical:heal', function(targetSrc, itemName, zone)
    local src    = source
    local xp     = ESX.GetPlayerFromId(src)
    if not xp then return end

    local target = tonumber(targetSrc) or src
    local med    = getMedical(target)
    local def    = MedConfig.HealingItems[itemName]
    if not def then return end

    -- Vérif EMS uniquement
    if def.emsOnly and xp.getJob().name ~= MedConfig.EmsJob then
        TriggerClientEvent('nova_medical:notify', src, 'Réservé au personnel EMS.', 'error')
        return
    end

    -- Retirer l'item de l'inventaire
    xp.removeInventoryItem(itemName, 1)

    -- Réanimation
    if def.revive and (med.state == 'laststand' or med.state == 'dead') then
        med.state   = 'injured'
        med.bleeding = false
        med.lastStandTimer = 0
        TriggerClientEvent('nova_medical:revived', target)
        TriggerClientEvent('nova_medical:notify', src, 'Patient réanimé avec succès.', 'success')
        syncToClient(target)
        syncToNearbyEms(target)
        saveToDB(target)
        return
    end

    -- Arrêt saignement
    if def.bleed then med.bleeding = false end

    -- Soins blessures
    if def.severity > 0 then
        local zones = def.zones
        local healAny = false
        for _, z in ipairs(zones) do if z == 'any' then healAny = true break end end

        for zoneName, zInjuries in pairs(med.injuries) do
            local zoneOk = healAny
            if not zoneOk then
                for _, z in ipairs(zones) do
                    if z == zoneName then zoneOk = true break end
                end
            end

            if zoneOk then
                local toRemove = {}
                for i, inj in ipairs(zInjuries) do
                    local typeOk = false
                    for _, h in ipairs(def.heals) do
                        if h == 'any' or h == inj.type then typeOk = true break end
                    end
                    if typeOk then
                        inj.severity = inj.severity - def.severity
                        if inj.severity <= 0 then
                            table.insert(toRemove, i)
                        end
                    end
                end
                for i = #toRemove, 1, -1 do
                    table.remove(zInjuries, toRemove[i])
                end
            end
        end
    end

    -- Recalculer état
    local totalInjuries = 0
    local maxSev = 0
    for _, zInjuries in pairs(med.injuries) do
        for _, inj in ipairs(zInjuries) do
            totalInjuries = totalInjuries + 1
            if inj.severity > maxSev then maxSev = inj.severity end
        end
    end

    if totalInjuries == 0 then
        med.state = 'conscious'
    elseif maxSev >= 3 or totalInjuries >= 4 then
        med.state = 'injured'
    else
        med.state = 'conscious'
    end

    syncToClient(target)
    if target ~= src then
        syncToNearbyEms(target)
        TriggerClientEvent('nova_medical:notify', target, 'Un EMS vous a soigné.', 'success')
    end
    saveToDB(target)
end)

-- ── Réapparition hôpital ──────────────────────────────────────────

RegisterNetEvent('nova_medical:respawn', function()
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp then return end
    local med = getMedical(src)
    if med.state ~= 'dead' and med.state ~= 'laststand' then return end

    -- Paiement
    if xp.getMoney() >= MedConfig.Death.respawnCost then
        xp.removeMoney(MedConfig.Death.respawnCost)
    end

    -- Reset médical
    PlayerMedical[src] = defaultMedical()
    syncToClient(src)
    TriggerClientEvent('nova_medical:doRespawn', src)
    saveToDB(src)
end)

-- ── Tick saignement (serveur) ─────────────────────────────────────

CreateThread(function()
    while true do
        Wait(1000)
        for src, med in pairs(PlayerMedical) do
            -- Saignement
            if med.bleeding and med.state ~= 'dead' then
                TriggerClientEvent('nova_medical:bleedTick', src)
            end
            -- Timer last stand
            if med.state == 'laststand' and med.lastStandTimer > 0 then
                if os.time() >= med.lastStandTimer then
                    med.state = 'dead'
                    med.bleeding = false
                    med.lastStandTimer = 0
                    syncToClient(src)
                    syncToNearbyEms(src)
                    saveToDB(src)
                    TriggerClientEvent('nova_medical:enterDead', src)
                end
            end
        end
    end
end)

-- ── Finalisation dossier patient ─────────────────────────────────

RegisterNetEvent('nova_medical:finaliser', function(data)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp then return end

    local targetSrcNum = tonumber(data.patientSrc)
    local xpTarget     = targetSrcNum and ESX.GetPlayerFromId(targetSrcNum)

    local patientId   = xpTarget and xpTarget.identifier or ('npc_' .. tostring(data.patientName or 'inconnu'):lower():gsub(' ', '_'))
    local patientName = tostring(data.patientName or 'Inconnu')
    local severity    = tostring(data.severity or 'Stable')
    local diagnosis   = tostring(data.diagnosis or ''):sub(1, 500)
    local notes       = tostring(data.notes or ''):sub(1, 1000)

    -- Calcul du coût selon sévérité
    local cost = 500
    if severity == 'Décédé'   then cost = math.random(4000, 8000)
    elseif severity == 'Critique' then cost = math.random(3000, 6000)
    elseif severity == 'Grave'    then cost = math.random(2000, 4000)
    elseif severity == 'Modérée'  then cost = math.random(1000, 2500)
    elseif severity == 'Légère'   then cost = math.random(300,  1000)
    end

    -- Insérer le dossier
    MySQL.insert(
        'INSERT INTO nova_hospital_records (patient_id, patient_name, ems_id, ems_name, diagnosis, exams, notes, severity, cost) VALUES (?,?,?,?,?,?,?,?,?)',
        {
            patientId, patientName,
            xp.identifier, xp.getName(),
            diagnosis,
            json.encode(data.results or {}),
            notes,
            severity,
            cost,
        }
    )

    -- Facturer le patient si joueur réel connecté
    if xpTarget then
        local money = xpTarget.getMoney()
        local charged = math.min(money, cost)
        if charged > 0 then
            xpTarget.removeMoney(charged)
        end
        TriggerClientEvent('nova_medical:notify', targetSrcNum,
            string.format('💊 Frais médicaux débités : %d $', charged), 'error')
    end

    TriggerClientEvent('nova_medical:notify', src,
        string.format('📋 Dossier enregistré — Frais : %d $', cost), 'success')
    TriggerClientEvent('nova_medical:finaliseDone', src, cost)
end)

-- ── Réanimation CPR (sans item) ───────────────────────────────────

RegisterNetEvent('nova_medical:cpr', function(targetSrc)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end

    local targetSrcNum = tonumber(targetSrc)
    if not targetSrcNum then return end

    local med = getMedical(targetSrcNum)

    if med.state == 'dead' then
        -- Patient décédé : CPR seul ne suffit pas, orienter vers défibrillateur
        TriggerClientEvent('nova_medical:notify', src,
            'Le patient est en arrêt cardiaque. Utilisez le défibrillateur.', 'error')
        return
    end

    if med.state ~= 'laststand' then
        TriggerClientEvent('nova_medical:notify', src,
            'Le patient n\'a pas besoin de réanimation.', 'warning')
        return
    end

    -- CPR sur laststand → stabilisation avec 75% de chance
    local roll = math.random(1, 100)
    if roll <= 75 then
        med.state          = 'injured'
        med.bleeding       = false
        med.lastStandTimer = 0
        TriggerClientEvent('nova_medical:revived',        targetSrcNum)
        TriggerClientEvent('nova_medical:notify',         src,          '💚 CPR réussi — patient stabilisé.', 'success')
        TriggerClientEvent('nova_medical:notify',         targetSrcNum, 'Vous avez été stabilisé(e) par massage cardiaque.', 'success')
        syncToClient(targetSrcNum)
        syncToNearbyEms(targetSrcNum)
        saveToDB(targetSrcNum)
    else
        -- Échec — prolonge légèrement le timer
        med.lastStandTimer = os.time() + 45
        TriggerClientEvent('nova_medical:notify', src,
            '❌ CPR inefficace. Continuez les compressions ou utilisez le défibrillateur.', 'error')
    end
end)

-- ── Exports ───────────────────────────────────────────────────────

exports('getPlayerMedical', function(src)
    return getMedical(src)
end)

exports('setPlayerState', function(src, state)
    local med = getMedical(src)
    med.state = state
    syncToClient(src)
end)

exports('addInjury', function(src, zone, injuryType, severity)
    local med = getMedical(src)
    if not med or med.state == 'dead' then return end
    zone     = zone or 'torso'
    severity = math.max(1, math.min(5, tonumber(severity) or 1))
    local def = MedConfig.InjuryTypes[injuryType]
    if not def then return end
    local existing = nil
    for _, inj in ipairs(med.injuries[zone] or {}) do
        if inj.type == injuryType then existing = inj break end
    end
    if existing then
        existing.severity = math.min(5, existing.severity + math.max(1, math.floor(severity * 0.5)))
    else
        table.insert(med.injuries[zone], { type=injuryType, severity=severity, ts=os.time() })
    end
    if def.bleed then med.bleeding = true end
    syncToClient(src)
    syncToNearbyEms(src)
end)

-- ── Demande de données patient (pour EMS) ────────────────────────

RegisterNetEvent('nova_medical:requestPatientData', function(targetSrc)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    local med = getMedical(targetSrc)
    TriggerClientEvent('nova_medical:patientDataResponse', src, targetSrc, med)
end)

-- ── Signal de détresse ────────────────────────────────────────────

RegisterNetEvent('nova_medical:distressSignal', function()
    local src  = source
    local xp   = ESX.GetPlayerFromId(src)
    if not xp then return end
    local coords = GetEntityCoords(GetPlayerPed(src))
    -- Envoyer à tous les EMS
    for _, pid in ipairs(ESX.GetPlayers()) do
        local xEms = ESX.GetPlayerFromId(pid)
        if xEms and xEms.getJob().name == MedConfig.EmsJob then
            TriggerClientEvent('nova_medical:distressSignal', pid, src, xp.getName(), { x=coords.x, y=coords.y, z=coords.z })
        end
    end
end)

-- ── Brancardage ───────────────────────────────────────────────────

RegisterNetEvent('nova_medical:startCarry', function(targetSrc, carrierNetId, patNetId)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    TriggerClientEvent('nova_medical:evt_beingPickedUp', targetSrc)
end)

RegisterNetEvent('nova_medical:stopCarry', function(targetSrc)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    TriggerClientEvent('nova_medical:evt_beingDropped', targetSrc)
end)

RegisterNetEvent('nova_medical:loadPatient', function(targetSrc, vehNetId, seat)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    TriggerClientEvent('nova_medical:evt_loadedInVehicle', targetSrc, vehNetId, seat)
end)

RegisterNetEvent('nova_medical:unloadPatient', function(targetSrc)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    TriggerClientEvent('nova_medical:evt_unloadedFromVehicle', targetSrc)
end)

-- ── Sac médical déployable ────────────────────────────────────────

local MedBags = {}   -- [bagId] = { src, x, y, z, items={[item]=qty} }
local bagCounter = 0

RegisterNetEvent('nova_medical:deployBag', function(x, y, z)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp then return end

    -- Vérifier que le joueur possède un sac_medical
    if not xp.getInventoryItem('sac_medical') or xp.getInventoryItem('sac_medical').count <= 0 then
        TriggerClientEvent('nova_medical:notify', src, 'Vous n\'avez pas de sac médical.', 'error')
        return
    end
    xp.removeInventoryItem('sac_medical', 1)

    bagCounter = bagCounter + 1
    local bagId = 'bag_' .. src .. '_' .. bagCounter

    -- Stock de départ
    local items = {}
    for item, def in pairs(MedConfig.BagStock) do
        items[item] = { item = item, label = def.label, qty = def.qty }
    end

    MedBags[bagId] = { src = src, x = x, y = y, z = z, items = items }

    -- Convertir en liste pour l'UI
    local itemList = {}
    for _, v in pairs(items) do table.insert(itemList, v) end

    -- Diffuser à tous les joueurs
    TriggerClientEvent('nova_medical:bag_deployed', -1, bagId, x, y, z, itemList)
    TriggerClientEvent('nova_medical:notify', src, 'Sac médical déployé.', 'success')
end)

RegisterNetEvent('nova_medical:takeBagItem', function(bagId, item)
    local src  = source
    local xp   = ESX.GetPlayerFromId(src)
    if not xp then return end

    local bag = MedBags[bagId]
    if not bag then return end
    if not bag.items[item] or bag.items[item].qty <= 0 then
        TriggerClientEvent('nova_medical:notify', src, 'Item épuisé dans le sac.', 'error')
        return
    end

    bag.items[item].qty = bag.items[item].qty - 1
    xp.addInventoryItem(item, 1)

    -- Mettre à jour les clients
    local itemList = {}
    for _, v in pairs(bag.items) do table.insert(itemList, v) end
    TriggerClientEvent('nova_medical:bag_updated', -1, bagId, itemList)
    TriggerClientEvent('nova_medical:notify', src, bag.items[item].label .. ' récupéré(e).', 'success')
end)

RegisterNetEvent('nova_medical:pickupBag', function(bagId)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp then return end

    local bag = MedBags[bagId]
    if not bag then return end

    -- Rendre le sac (si pas vide on remet quand même)
    xp.addInventoryItem('sac_medical', 1)
    MedBags[bagId] = nil

    TriggerClientEvent('nova_medical:bag_removed', -1, bagId)
    TriggerClientEvent('nova_medical:notify', src, 'Sac médical récupéré.', 'success')
end)

-- ── Debug ─────────────────────────────────────────────────────────

RegisterNetEvent('nova_medical:debugInjure', function(zone, injuryType, severity)
    local src = source
    local med = getMedical(src)
    if med.state == 'dead' then return end
    zone     = zone or 'torso'
    severity = math.max(1, math.min(5, tonumber(severity) or 2))
    injuryType = injuryType or 'gunshot'
    local def = MedConfig.InjuryTypes[injuryType]
    if not def then return end
    table.insert(med.injuries[zone], { type=injuryType, severity=severity, ts=os.time() })
    if def.bleed then med.bleeding = true end
    if severity >= 4 then
        med.state = 'laststand'
        med.lastStandTimer = os.time() + MedConfig.Death.lastStandTime
        TriggerClientEvent('nova_medical:enterLastStand', src, MedConfig.Death.lastStandTime)
    elseif severity >= 2 then
        med.state = 'injured'
    end
    syncToClient(src)
    syncToNearbyEms(src)
end)

RegisterNetEvent('nova_medical:debugClear', function()
    local src = source
    PlayerMedical[src] = defaultMedical()
    syncToClient(src)
    TriggerClientEvent('nova_medical:notify', src, 'État médical réinitialisé.', 'success')
end)

-- ═══════════════════════════════════════════════════════════════
--  MONITORING CONTINU
--  [targetSrc] = { attachedBySrc, vitals={bpm,spo2,bp_sys,bp_dia}, baseVitals={...} }
-- ═══════════════════════════════════════════════════════════════

local function broadcastMonitoringToAllEms(targetSrc, vitals)
    for _, pid in ipairs(ESX.GetPlayers()) do
        local xEms = ESX.GetPlayerFromId(pid)
        if xEms and xEms.getJob().name == MedConfig.EmsJob then
            TriggerClientEvent('nova_medical:monitoringUpdate', pid, targetSrc, vitals)
        end
    end
end

-- ── Attacher monitoring ───────────────────────────────────────────

RegisterNetEvent('nova_medical:attachMonitoring', function(targetSrc, vitals)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    if not targetSrc or targetSrc <= 0 then return end

    local v = {
        bpm    = math.floor(tonumber(vitals.bpm)    or 72),
        spo2   = math.floor(tonumber(vitals.spo2)   or 98),
        bp_sys = math.floor(tonumber(vitals.bp_sys) or 120),
        bp_dia = math.floor(tonumber(vitals.bp_dia) or 80),
    }
    MonitoredPatients[targetSrc] = {
        attachedBySrc = src,
        vitals        = v,
        baseVitals    = { bpm = v.bpm, spo2 = v.spo2, bp_sys = v.bp_sys, bp_dia = v.bp_dia },
    }

    -- Notifier tous les EMS (DrawText3D sur tous les clients EMS)
    for _, pid in ipairs(ESX.GetPlayers()) do
        local xEms = ESX.GetPlayerFromId(pid)
        if xEms and xEms.getJob().name == MedConfig.EmsJob then
            TriggerClientEvent('nova_medical:monitoringStart', pid, targetSrc, v)
        end
    end
end)

-- ── Déconnecter monitoring ────────────────────────────────────────

RegisterNetEvent('nova_medical:detachMonitoring', function(targetSrc)
    local src = source
    local xp  = ESX.GetPlayerFromId(src)
    if not xp or xp.getJob().name ~= MedConfig.EmsJob then return end
    if not MonitoredPatients[targetSrc] then return end

    MonitoredPatients[targetSrc] = nil
    for _, pid in ipairs(ESX.GetPlayers()) do
        local xEms = ESX.GetPlayerFromId(pid)
        if xEms and xEms.getJob().name == MedConfig.EmsJob then
            TriggerClientEvent('nova_medical:monitoringStop', pid, targetSrc)
        end
    end
end)

-- ── Tick drift des constantes (toutes les 5s) ─────────────────────

local function driftVal(val, baseVal, maxDev, step)
    local d = math.random(-step, step)
    local newVal = math.floor(val + d)
    if math.abs(newVal - baseVal) > maxDev then
        newVal = newVal - (d >= 0 and 1 or -1)
    end
    return newVal
end

CreateThread(function()
    while true do
        Wait(5000)
        for targetSrc, session in pairs(MonitoredPatients) do
            local v    = session.vitals
            local base = session.baseVitals
            local med  = PlayerMedical[targetSrc]

            -- Micro-variations autour de la ligne de base
            v.bpm    = math.max(20,  math.min(220, driftVal(v.bpm,    base.bpm,    12, 3)))
            v.spo2   = math.max(50,  math.min(100, driftVal(v.spo2,   base.spo2,   4,  1)))
            v.bp_sys = math.max(40,  math.min(220, driftVal(v.bp_sys, base.bp_sys, 12, 4)))
            v.bp_dia = math.max(20,  math.min(140, driftVal(v.bp_dia, base.bp_dia, 8,  2)))

            -- Dégradation si état critique
            if med and med.state == 'laststand' then
                v.bpm    = math.min(220, v.bpm    + math.random(2, 6))
                v.spo2   = math.max(50,  v.spo2   - math.random(1, 3))
                v.bp_sys = math.max(40,  v.bp_sys - math.random(2, 6))
                v.bp_dia = math.max(20,  v.bp_dia - math.random(1, 3))
            -- Stabilisation si état conscient et soins effectués
            elseif med and med.state == 'conscious' then
                v.bpm    = math.floor(v.bpm    * 0.95 + base.bpm    * 0.05 + math.random(-1, 1))
                v.spo2   = math.min(100, v.spo2 + (v.spo2 < base.spo2 and 1 or 0))
                v.bp_sys = math.floor(v.bp_sys * 0.96 + base.bp_sys * 0.04)
            end

            broadcastMonitoringToAllEms(targetSrc, v)
        end
    end
end)
