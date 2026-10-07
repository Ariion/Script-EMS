-- Pont telephone (CLIENT) : point d'entrée unique pour ouvrir l'app.
Phone = {}
local detected = Config.Phone

if detected == 'auto' then
  if GetResourceState('lb-phone') == 'started' then detected = 'lb-phone'
  elseif GetResourceState('qb-phone') == 'started' then detected = 'qb-phone'
  elseif GetResourceState('npwd') == 'started' then detected = 'npwd'
  else detected = 'standalone' end
end
Phone.name = detected

-- ── Mode standalone / lb-phone / qb-phone ────────────────────────────
local function OpenStandalone()
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', businesses = Config.Businesses })
end

-- ── Mode NPWD ─────────────────────────────────────────────────────────
-- L'agenda est une app NPWD chargée via Module Federation.
-- La commande /agenda affiche le téléphone ; le joueur navigue ensuite
-- vers l'icône Agenda sur l'écran d'accueil (ou NPWD l'ouvre directement
-- si l'API npwd:app:open est disponible dans la version installée).
local function OpenNPWD()
  pcall(function() exports['npwd']:setPhoneVisible(true) end)
  -- Tentative de navigation directe vers l'app (API disponible sur certaines versions)
  CreateThread(function()
    Wait(150)
    pcall(function()
      -- NPWD >= 1.1 expose un event client pour naviguer vers une app
      TriggerEvent('npwd:app:open', '/agenda')
    end)
  end)
end

-- ── API publique ──────────────────────────────────────────────────────

function Phone.OpenApp()
  if detected == 'npwd' then
    OpenNPWD()
  else
    OpenStandalone()
  end
end

function Phone.OnClose()
  -- Standalone/lb-phone/qb-phone : masque la NUI
  if detected ~= 'npwd' then
    SetNuiFocus(false, false)
  end
  -- NPWD : la navigation retour est gérée par le composant React (history.push('/'))
end

-- Écoute optionnelle d'un event NPWD pour ouvrir l'agenda depuis le téléphone
if detected == 'npwd' then
  RegisterNetEvent('agenda:openFromNPWD', function()
    OpenNPWD()
  end)
end
