-- ═══════════════════════════════════════════════════════════════
--  nova_medical — HUD EMS (mini vitaux patient suivi)
-- ═══════════════════════════════════════════════════════════════

local trackedPatient = nil  -- { src, name, medical, lastExamResults }
local HUD_UPDATE_MS  = 5000 -- refresh toutes les 5s si on a un patient suivi

-- ── Mettre à jour le HUD avec les données d'un patient ───────────

function HudTrackPatient(src, name, medical, results)
    trackedPatient = { src = src, name = name, medical = medical, results = results or {} }
    HudRefresh()
end

function HudClear()
    trackedPatient = nil
    SendNUIMessage({ action = 'hudClear' })
end

function HudRefresh()
    if not trackedPatient then return end

    local med = trackedPatient.medical or {}
    local stateMap = {
        conscious = { label = 'Stable',   cls = 'conscious' },
        injured   = { label = 'Blessé',   cls = 'injured'   },
        laststand = { label = 'CRITIQUE', cls = 'laststand' },
        dead      = { label = 'Décédé',   cls = 'dead'      },
    }
    local stateInfo = stateMap[med.state or 'conscious'] or stateMap.conscious

    -- Compter blessures
    local injCount = 0
    for _, zInj in pairs(med.injuries or {}) do
        injCount = injCount + #zInj
    end

    -- Récupérer les derniers vitaux connus depuis les résultats d'examens
    local bpm  = '—'
    local spo2 = '—'
    local bp   = '—'

    for _, r in ipairs(trackedPatient.results or {}) do
        if r.type == 'bp'   then bpm = tostring(r.pulse or '—'); bp = (r.systolic or '—') .. '/' .. (r.diastolic or '—') end
        if r.type == 'spo2' then spo2 = tostring(r.spo2 or '—') end
        if r.type == 'ecg'  then bpm = tostring(r.bpm or '—') end
    end

    SendNUIMessage({
        action     = 'hudUpdate',
        active     = true,
        name       = trackedPatient.name,
        state      = stateInfo.cls,
        stateLabel = stateInfo.label,
        bpm        = bpm,
        spo2       = spo2,
        bp         = bp,
        injuries   = injCount,
        bleeding   = med.bleeding or false,
    })
end

-- ── Quand un EMS ouvre l'examen → tracker le patient ─────────────
-- Appelé depuis examination.lua

function HudSetFromExamSession(session)
    if not session then HudClear() return end
    HudTrackPatient(session.patientSrc, session.patientName, session.medical, session.results)
end

-- ── Mise à jour quand le patient change d'état ───────────────────

RegisterNetEvent('nova_medical:patientUpdate', function(patientSrc, patientName, medical)
    if trackedPatient and trackedPatient.src == patientSrc then
        trackedPatient.medical = medical
        trackedPatient.name    = patientName
        HudRefresh()
    end
end)

-- ── Commande pour effacer le suivi ───────────────────────────────

RegisterCommand('clrpatient', function()
    HudClear()
    lib.notify({ description = 'Suivi patient effacé.', type = 'inform', duration = 2000 })
end, false)

-- ── Thread de refresh périodique ─────────────────────────────────

CreateThread(function()
    while true do
        Wait(HUD_UPDATE_MS)
        if trackedPatient and trackedPatient.src and trackedPatient.src > 0 then
            -- Vérifier que le patient est toujours connecté et proche
            local pid = GetPlayerFromServerId(trackedPatient.src)
            if pid >= 0 then
                local myPed  = PlayerPedId()
                local patPed = GetPlayerPed(pid)
                if patPed and patPed ~= 0 then
                    local dist = #(GetEntityCoords(myPed) - GetEntityCoords(patPed))
                    if dist > 100.0 then
                        -- Patient trop loin, on garde quand même le suivi mais on signale
                        SendNUIMessage({ action = 'hudDistant', dist = math.floor(dist) })
                    end
                end
            end
        end
    end
end)
