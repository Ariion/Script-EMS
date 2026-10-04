-- Pont telephone (CLIENT) : un seul point d'entree pour ouvrir l'app.
Phone = {}
local detected = Config.Phone

if detected == 'auto' then
  if GetResourceState('lb-phone') == 'started' then detected = 'lb-phone'
  elseif GetResourceState('qb-phone') == 'started' then detected = 'qb-phone'
  elseif GetResourceState('npwd') == 'started' then detected = 'npwd'
  else detected = 'standalone' end
end
Phone.name = detected

function Phone.OpenApp()
  if detected == 'lb-phone' then
    -- TODO adaptateur lb-phone
    OpenStandalone()
  elseif detected == 'qb-phone' then
    -- TODO adaptateur qb-phone
    OpenStandalone()
  elseif detected == 'npwd' then
    -- TODO adaptateur NPWD (external app) -> dev gratuit ici
    OpenStandalone()
  else
    OpenStandalone()
  end
end

function OpenStandalone()
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', businesses = Config.Businesses })
end
