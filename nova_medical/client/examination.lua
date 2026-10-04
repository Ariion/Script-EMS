-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Examens diagnostiques (EMS)
-- ═══════════════════════════════════════════════════════════════

local examSession  = nil   -- { patientSrc, patientName, medical, results={}, notes='' }
local pendingAnim  = nil   -- flag lu par le thread persistant

-- Animations par type d'examen (confirmées dans esx_animations config.lua)
-- type 'scenario' : TaskStartScenarioInPlace | type 'anim' : TaskPlayAnim
local examAnimMap = {
    initial      = { type = 'scenario', name = 'CODE_HUMAN_MEDIC_KNEEL'                                            },
    bp           = { type = 'anim',     dict = 'mini@repair',                             clip = 'fixing_a_ped'   },
    spo2         = { type = 'anim',     dict = 'amb@code_human_police_investigate@idle_b', clip = 'idle_f'         },
    neuro        = { type = 'anim',     dict = 'mini@safe_cracking',                      clip = 'idle_base'       },
    ecg          = { type = 'anim',     dict = 'mini@cpr@char_a@cpr_str',                 clip = 'cpr_pumpchest'   },
    auscultation = { type = 'scenario', name = 'CODE_HUMAN_MEDIC_KNEEL'                                            },
    glucose      = { type = 'anim',     dict = 'mini@repair',                             clip = 'fixing_a_ped'   },
    temp         = { type = 'anim',     dict = 'amb@code_human_police_investigate@idle_b', clip = 'idle_f'         },
}

-- Thread persistant : lit le flag et joue l'animation dans le bon contexte Lua
CreateThread(function()
    while true do
        Wait(0)
        if pendingAnim then
            local examId  = pendingAnim.examId
            local duration = pendingAnim.duration
            pendingAnim   = nil

            local anim = examAnimMap[examId]
            if anim then
                local ped = PlayerPedId()
                if anim.type == 'scenario' then
                    print('[nova_medical] Scenario: ' .. anim.name)
                    TaskStartScenarioInPlace(ped, anim.name, 0, true)
                    Wait(duration + 200)
                    ClearPedTasks(ped)
                elseif anim.type == 'anim' then
                    RequestAnimDict(anim.dict)
                    local t = GetGameTimer() + 4000
                    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < t do
                        Wait(50)
                    end
                    if HasAnimDictLoaded(anim.dict) then
                        print('[nova_medical] Anim: ' .. anim.dict .. ' / ' .. anim.clip)
                        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, -3.0, duration, 1, 0, false, false, false)
                        Wait(duration + 200)
                        StopAnimTask(ped, anim.dict, anim.clip, 2.0)
                    else
                        print('[nova_medical] ANIM DICT LOAD FAILED: ' .. anim.dict)
                    end
                end
            end
        end
    end
end)

-- ── Génération des résultats d'examen ────────────────────────────

local function rand(a, b) return math.random(a, b) end

local function generateExamResult(examId, med)
    local injuries = med.injuries or {}
    local state    = med.state or 'conscious'
    local diseases = med.diseases or {}

    -- Sévérité max globale
    local maxSev = 0
    local injCount = 0
    for _, zInj in pairs(injuries) do
        for _, inj in ipairs(zInj) do
            injCount = injCount + 1
            if inj.severity > maxSev then maxSev = inj.severity end
        end
    end

    local bpm  = rand(62, 80)
    local spo2 = rand(97, 100)
    local temp = (rand(365, 372)) / 10
    local sys  = rand(110, 128)
    local dia  = rand(68, 80)

    -- Ajuster selon état
    if state == 'dead' then
        bpm = 0; spo2 = 0; temp = 34.5; sys = 0; dia = 0
    elseif state == 'laststand' then
        bpm  = rand(20, 45);  spo2 = rand(70, 82)
        temp = rand(344, 360)/10; sys = rand(50, 80); dia = rand(28, 50)
    elseif maxSev >= 4 or injCount >= 5 then
        bpm  = rand(100, 145); spo2 = rand(84, 92)
        temp = rand(376, 393)/10; sys = rand(88, 118); dia = rand(55, 75)
    elseif maxSev >= 2 or injCount >= 2 then
        bpm  = rand(85, 110); spo2 = rand(91, 96)
        temp = rand(370, 381)/10; sys = rand(115, 148); dia = rand(72, 90)
    end

    -- Saignement actif → aggrave
    if med.bleeding then
        bpm  = bpm + rand(10, 20)
        spo2 = spo2 - rand(3, 6)
    end

    -- Blessures torse → SpO2 basse
    local torsoInj = injuries.torso or {}
    for _, inj in ipairs(torsoInj) do
        if inj.type == 'internal' or inj.type == 'explosion' then
            spo2 = spo2 - (inj.severity * 2)
        end
    end

    -- Maladies
    if diseases.hypertension then sys = sys + math.floor((diseases.hypertension.severity or 1) * 8) end
    if diseases.infection     then bpm = bpm + math.floor((diseases.infection.severity or 1) * 10); temp = temp + 0.4 * (diseases.infection.severity or 1) end
    if diseases.arrhythmia    then bpm = bpm + rand(-20, 30) end
    if diseases.pneumothorax  then spo2 = spo2 - math.floor((diseases.pneumothorax.severity or 1) * 4) end

    -- Clamp
    bpm  = math.max(0, math.min(220, math.floor(bpm)))
    spo2 = math.max(0, math.min(100, math.floor(spo2)))
    temp = math.max(30, math.min(43, math.floor(temp * 10) / 10))
    sys  = math.max(0, math.min(220, math.floor(sys)))
    dia  = math.max(0, math.min(140, math.floor(dia)))

    local ts = math.floor(GetGameTimer() / 1000)

    if examId == 'initial' then
        local stateLabel = ({ conscious='Conscient', injured='Blessé', laststand='Critique', dead='Décédé' })[state] or state
        local sevLabel   = maxSev >= 4 and 'Grave' or maxSev >= 2 and 'Modérée' or 'Légère'
        return {
            type      = 'initial',
            state     = state,
            stateLabel= stateLabel,
            severity  = sevLabel,
            injuries  = injCount,
            pulse     = bpm .. ' bpm',
            breathing = spo2 >= 95 and 'Régulière' or spo2 >= 88 and 'Difficile' or 'Agonique',
            ts        = ts,
        }

    elseif examId == 'bp' then
        local eval = 'normale'
        if sys >= 140 or dia >= 90 then eval = 'hypertension'
        elseif sys < 90 then eval = 'hypotension' end
        return { type='bp', systolic=sys, diastolic=dia, pulse=bpm, evaluation=eval, ts=ts }

    elseif examId == 'spo2' then
        local eval = spo2 >= 95 and 'normal' or spo2 >= 88 and 'hypoxie légère' or 'hypoxie sévère'
        local detail = nil
        if spo2 < 88 then detail = 'Détresse respiratoire' end
        return { type='spo2', spo2=spo2, evaluation=eval, detail=detail, ts=ts }

    elseif examId == 'neuro' then
        local gcsO = 4; local gcsV = 5; local gcsM = 6
        local headInj = injuries.head or {}
        for _, inj in ipairs(headInj) do
            gcsO = math.max(1, gcsO - math.floor(inj.severity * 0.5))
            gcsV = math.max(1, gcsV - math.floor(inj.severity * 0.4))
            gcsM = math.max(1, gcsM - math.floor(inj.severity * 0.3))
        end
        if state == 'laststand' then gcsO=1; gcsV=1; gcsM=2 end
        local gcs = gcsO + gcsV + gcsM
        local eval = gcs >= 13 and 'normal' or gcs >= 9 and 'altéré' or 'critique'
        return { type='neuro', gcs=gcs, gcsO=gcsO, gcsV=gcsV, gcsM=gcsM, pupils='réactives', evaluation=eval, ts=ts }

    elseif examId == 'ecg' then
        local rhythm = 'normal'
        local anomalies = {}
        if bpm > 120 then rhythm = 'tachycardie'; table.insert(anomalies, 'Tachycardie sinusale') end
        if bpm < 50  then rhythm = 'bradycardie'; table.insert(anomalies, 'Bradycardie') end
        if state == 'laststand' then rhythm = 'fibrillation'; table.insert(anomalies, 'Fibrillation ventriculaire') end
        if state == 'dead' then rhythm = 'arrêt cardiaque' end
        if diseases.arrhythmia then rhythm = 'arythmie'; table.insert(anomalies, 'Arythmie connue') end
        return { type='ecg', rhythm=rhythm, bpm=bpm, pr=rand(120,200), qrs=rand(80,120), anomalies=anomalies, evaluation=rhythm, ts=ts }

    elseif examId == 'auscultation' then
        local heartSound = bpm <= 100 and 'Régulier' or 'Irrégulier'
        local breathing2  = spo2 >= 95 and 'Vésiculaire' or 'Diminué'
        local rales       = (spo2 < 90 or (diseases.pneumothorax)) and 'présents' or 'absent'
        local murmur      = 'absent'
        return { type='auscultation', heartSound=heartSound, bpm=bpm, breathing=breathing2, rales=rales, murmur=murmur, ts=ts }

    elseif examId == 'glucose' then
        local val  = rand(39, 99) / 10
        if diseases.diabetes then val = rand(28, 140) / 10 end
        local eval = val < 3.9 and 'hypoglycémie' or val > 6.1 and 'hyperglycémie' or 'normal'
        return { type='glucose', value=val, unit='mmol/L', evaluation=eval, ts=ts }

    elseif examId == 'temp' then
        local eval = temp < 36.0 and 'hypothermie' or temp > 38.5 and 'fièvre' or 'normale'
        if diseases.hypothermia then temp = temp - (diseases.hypothermia.severity * 0.8) end
        return { type='temp', value=string.format('%.1f', temp), unit='°C', evaluation=eval, ts=ts }
    end

    return nil
end

-- ── Ouvrir le menu d'examen EMS ───────────────────────────────────

function OpenExamMenu(targetSrc, targetName, targetMedical)
    -- Conserver résultats et notes si même patient
    local prevResults = {}
    local prevNotes   = ''
    if examSession and examSession.patientSrc == targetSrc then
        prevResults = examSession.results or {}
        prevNotes   = examSession.notes   or ''
    end

    examSession = {
        patientSrc  = targetSrc,
        patientName = targetName,
        medical     = targetMedical,
        results     = prevResults,
        notes       = prevNotes,
    }

    SetUiOpen(true)
    SetNuiFocus(true, true)
    -- Tracker le patient dans le HUD
    if HudSetFromExamSession then
        HudSetFromExamSession(examSession)
    end
    SendNUIMessage({
        action      = 'openExam',
        patientName = targetName,
        medical     = targetMedical,
        isEms       = true,
        prevResults = prevResults,
        prevNotes   = prevNotes,
        sessionId   = tostring(targetSrc) .. '_' .. tostring(math.floor(GetGameTimer() / 1000)),
    })
end

-- ── Lancer un examen ──────────────────────────────────────────────

RegisterNUICallback('startExam', function(data, cb)
    cb('ok')
    if not examSession then return end
    local examId = data.examId

    local examDef = nil
    for _, e in ipairs(MedConfig.Exams) do
        if e.id == examId then examDef = e break end
    end
    if not examDef then return end

    SendNUIMessage({ action = 'examLoading', examId = examId, duration = examDef.duration })
    pendingAnim = { examId = examId, duration = examDef.duration }
    Wait(examDef.duration)

    local result = generateExamResult(examId, examSession.medical)
    if not result then return end

    table.insert(examSession.results, result)
    SendNUIMessage({ action = 'addExamResult', result = result })
    -- Mettre à jour le HUD
    if HudSetFromExamSession then HudSetFromExamSession(examSession) end
end)

-- ── Sauvegarde des notes cliniques ───────────────────────────────

RegisterNUICallback('saveNotes', function(data, cb)
    cb('ok')
    if examSession then
        examSession.notes = data.notes or ''
    end
end)

-- ── Finalisation dossier ──────────────────────────────────────────

RegisterNUICallback('finaliser', function(data, cb)
    cb('ok')
    if not examSession then return end

    -- Calculer sévérité globale
    local severity = 'Stable'
    if examSession.medical then
        local med     = examSession.medical
        local maxSev  = 0
        local injCount = 0
        for _, zInj in pairs(med.injuries or {}) do
            for _, inj in ipairs(zInj) do
                injCount = injCount + 1
                if inj.severity > maxSev then maxSev = inj.severity end
            end
        end
        if     med.state == 'dead'      then severity = 'Décédé'
        elseif med.state == 'laststand' then severity = 'Critique'
        elseif maxSev >= 4 or injCount >= 5 then severity = 'Grave'
        elseif maxSev >= 2 or injCount >= 2 then severity = 'Modérée'
        elseif injCount > 0 then severity = 'Légère'
        end
    end

    TriggerServerEvent('nova_medical:finaliser', {
        patientSrc  = examSession.patientSrc,
        patientName = examSession.patientName,
        results     = examSession.results,
        notes       = examSession.notes,
        diagnosis   = data.diagnosis or '',
        severity    = severity,
    })
end)

RegisterNetEvent('nova_medical:finaliseDone', function(cost)
    SendNUIMessage({ action = 'finaliseDone', cost = cost })
end)

-- ── Étape de protocole déclenchée depuis NUI ──────────────────────

RegisterNUICallback('protocolStep', function(data, cb)
    cb('ok')
    if not examSession then return end
    local examId = data.examId

    local examDef = nil
    for _, e in ipairs(MedConfig.Exams) do
        if e.id == examId then examDef = e break end
    end
    if not examDef then return end

    SendNUIMessage({ action = 'examLoading', examId = examId, duration = examDef.duration })
    pendingAnim = { examId = examId, duration = examDef.duration }
    Wait(examDef.duration)
    local result = generateExamResult(examId, examSession.medical)
    if not result then return end
    table.insert(examSession.results, result)
    SendNUIMessage({ action = 'addExamResult', result = result })
end)

-- ── Mise à jour des données patient ──────────────────────────────

RegisterNetEvent('nova_medical:patientUpdate', function(patientSrc, patientName, medical)
    if examSession and examSession.patientSrc == patientSrc then
        examSession.medical = medical
        SendNUIMessage({ action = 'patientUpdate', medical = medical })
    end
end)

-- ── ox_target sur joueurs (EMS) ───────────────────────────────────

CreateThread(function()
    Wait(2000)
    exports['ox_target']:addGlobalPlayer({
        {
            name  = 'nova_medical_examine',
            icon  = 'fas fa-stethoscope',
            label = 'Examiner le patient',
            distance = 3.0,
            canInteract = function()
                return GetIsEms()
            end,
            onSelect = function(data)
                local pid  = NetworkGetPlayerIndexFromPed(data.entity)
                local sid  = GetPlayerServerId(pid)
                if sid <= 0 then return end
                local name = GetPlayerName(pid)
                TriggerServerEvent('nova_medical:requestPatientData', sid)
                local timeout = GetGameTimer() + 3000
                CreateThread(function()
                    while GetGameTimer() < timeout do
                        Wait(100)
                        if _pendingPatient and _pendingPatient.src == sid then
                            OpenExamMenu(sid, name, _pendingPatient.medical)
                            _pendingPatient = nil
                            return
                        end
                    end
                end)
            end,
        },
        {
            name  = 'nova_medical_treat',
            icon  = 'fas fa-first-aid',
            label = 'Soigner le patient',
            distance = 3.0,
            canInteract = function()
                return GetIsEms()
            end,
            onSelect = function(data)
                local pid = NetworkGetPlayerIndexFromPed(data.entity)
                local sid = GetPlayerServerId(pid)
                if sid <= 0 then return end
                OpenTreatMenu(sid)
            end,
        },
        {
            name     = 'nova_medical_cpr',
            icon     = 'fas fa-heart',
            label    = 'Massage cardiaque (CPR)',
            distance = 3.0,
            canInteract = function()
                return GetIsEms()
            end,
            onSelect = function(data)
                local pid = NetworkGetPlayerIndexFromPed(data.entity)
                local sid = GetPlayerServerId(pid)
                if sid <= 0 then return end
                DoCPR(sid)
            end,
        },
        {
            name     = 'nova_medical_defib',
            icon     = 'fas fa-bolt',
            label    = 'Défibrillateur',
            distance = 3.0,
            canInteract = function()
                return GetIsEms()
            end,
            onSelect = function(data)
                local pid = NetworkGetPlayerIndexFromPed(data.entity)
                local sid = GetPlayerServerId(pid)
                if sid <= 0 then return end
                UseDefibrillator(sid)
            end,
        },
    })
end)

_pendingPatient = nil

RegisterNetEvent('nova_medical:patientDataResponse', function(patientSrc, medical)
    _pendingPatient = { src = patientSrc, medical = medical }
end)

-- ── NUI Callback : clear patient HUD ─────────────────────────────

RegisterNUICallback('hudClear', function(_, cb)
    cb('ok')
    if HudClear then HudClear() end
end)

-- ── Ouverture depuis une ressource externe (ex: nova_testmode) ────
-- Utilisable via TriggerEvent('nova_medical:openNpcExamUI', name, medical)
-- ou exports['nova_medical']:openNpcExamMenu(name, medical)

AddEventHandler('nova_medical:openNpcExamUI', function(name, medical)
    OpenExamMenu(-1, name or 'NPC Patient', medical or {
        state    = 'conscious',
        injuries = { head={}, torso={}, leftArm={}, rightArm={}, leftLeg={}, rightLeg={} },
        diseases = {},
        bleeding = false,
    })
end)

exports('openNpcExamMenu', function(name, medical)
    OpenExamMenu(-1, name or 'NPC Patient', medical or {
        state    = 'conscious',
        injuries = { head={}, torso={}, leftArm={}, rightArm={}, leftLeg={}, rightLeg={} },
        diseases = {},
        bleeding = false,
    })
end)

-- ── Server : envoyer données patient à l'EMS qui les demande ─────

-- (event géré côté serveur dans main.lua)
-- On enregistre l'event côté serveur via RegisterNetEvent dans server/main.lua
