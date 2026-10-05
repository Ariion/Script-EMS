-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Monitoring continu patient (DrawText3D EMS)
--  Affiche les constantes du patient au-dessus de sa tête,
--  visible uniquement par les EMS tant que le monitoring est actif.
-- ═══════════════════════════════════════════════════════════════

-- Table locale : [targetSrc] = { vitals={bpm,spo2,bp_sys,bp_dia} }
local monitoredPatients = {}

-- ── Helper DrawText3D ─────────────────────────────────────────────

local function DrawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    local cam  = GetGameplayCamCoords()
    local dist = #(vector3(cam.x, cam.y, cam.z) - vector3(x, y, z))
    if dist > 20.0 then return end
    local scale = math.min(0.50, (1 / dist) * 1.8 * ((1 / GetGameplayCamFov()) * 100))
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextColour(220, 240, 255, 215)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    EndTextCommandDisplayText(sx, sy)
end

-- ── NUI : attacher monitoring ─────────────────────────────────────

RegisterNUICallback('attachMonitoring', function(data, cb)
    cb('ok')
    if not examSession then return end
    local targetSrc = examSession.patientSrc
    if not targetSrc or targetSrc <= 0 then return end

    local vitals = {
        bpm    = math.floor(tonumber(data.bpm)    or 72),
        spo2   = math.floor(tonumber(data.spo2)   or 98),
        bp_sys = math.floor(tonumber(data.bp_sys) or 120),
        bp_dia = math.floor(tonumber(data.bp_dia) or 80),
    }
    TriggerServerEvent('nova_medical:attachMonitoring', targetSrc, vitals)
end)

-- ── NUI : déconnecter monitoring ──────────────────────────────────

RegisterNUICallback('detachMonitoring', function(_, cb)
    cb('ok')
    local targetSrc = examSession and examSession.patientSrc
    if targetSrc then
        TriggerServerEvent('nova_medical:detachMonitoring', targetSrc)
    end
end)

-- ── Events réseau (broadcast depuis le serveur à tous les EMS) ────

RegisterNetEvent('nova_medical:monitoringStart', function(targetSrc, vitals)
    monitoredPatients[targetSrc] = { vitals = vitals }
    -- Si c'est le patient qu'on a en examen, mettre à jour le NUI
    if examSession and examSession.patientSrc == targetSrc then
        SendNUIMessage({ action = 'monitoringAttached' })
    end
end)

RegisterNetEvent('nova_medical:monitoringUpdate', function(targetSrc, vitals)
    if monitoredPatients[targetSrc] then
        monitoredPatients[targetSrc].vitals = vitals
        -- Mettre à jour le panneau NUI si ce patient est en cours d'examen
        if examSession and examSession.patientSrc == targetSrc then
            SendNUIMessage({ action = 'monitoringUpdate', vitals = vitals })
        end
    end
end)

RegisterNetEvent('nova_medical:monitoringStop', function(targetSrc)
    monitoredPatients[targetSrc] = nil
    if examSession and examSession.patientSrc == targetSrc then
        SendNUIMessage({ action = 'monitoringDetached' })
    end
end)

-- ── Thread DrawText3D ─────────────────────────────────────────────

CreateThread(function()
    while true do
        local hasPatients = next(monitoredPatients) ~= nil
        if hasPatients and GetIsEms and GetIsEms() then
            Wait(0)
            for targetSrc, session in pairs(monitoredPatients) do
                local pid = GetPlayerFromServerId(targetSrc)
                if pid >= 0 then
                    local patPed = GetPlayerPed(pid)
                    if patPed and patPed ~= 0 and DoesEntityExist(patPed) then
                        local headBone = GetPedBoneIndex(patPed, 31086) -- SKEL_Head
                        local hx, hy, hz = GetWorldPositionOfEntityBone(patPed, headBone)
                        local v = session.vitals

                        -- Couleurs GTA natives selon criticité
                        local bpmCol  = (v.bpm > 120 or v.bpm < 50) and '~r~' or '~g~'
                        local spo2Col = v.spo2 < 90 and '~r~' or v.spo2 < 95 and '~y~' or '~g~'
                        local bpCol   = v.bp_sys < 90 and '~r~' or v.bp_sys > 140 and '~y~' or '~w~'

                        local line = string.format(
                            '~b~♥ ' .. bpmCol .. '%d bpm~s~  |  ~b~O₂ ' .. spo2Col .. '%d%%~s~  |  ~b~TA ' .. bpCol .. '%d/%d~s~',
                            v.bpm, v.spo2, v.bp_sys, v.bp_dia
                        )
                        DrawText3D(hx, hy, hz + 0.25, line)
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)
