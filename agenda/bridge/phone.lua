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

-- ── Ouverture de l'overlay agenda ────────────────────────────────────
local function OpenStandalone()
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', businesses = Config.Businesses })
end

function Phone.OpenApp()
  if detected == 'npwd' then
    -- Masquer le téléphone NPWD pour laisser la place à l'overlay
    pcall(function() exports['npwd']:setPhoneVisible(false) end)
    Wait(80)
  end
  OpenStandalone()
end

-- ── Appelé à la fermeture de l'agenda ────────────────────────────────
function Phone.OnClose()
  if detected == 'npwd' then
    -- Remettre le téléphone NPWD au premier plan
    pcall(function() exports['npwd']:setPhoneVisible(true) end)
  end
end

-- ── NPWD : enregistrer le joueur dans le carnet de contacts ──────────
-- (CLIENT-side) Déclenché lorsque l'agenda est chargé et que NPWD est actif.
-- Le vrai enregistrement (newPlayer) se fait côté serveur dans bridge/framework.lua
if detected == 'npwd' then
  -- Écoute d'un event optionnel émis depuis l'interface NPWD pour ouvrir l'agenda
  RegisterNetEvent('agenda:openFromNPWD', function()
    Phone.OpenApp()
  end)
end
