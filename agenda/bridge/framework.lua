-- Pont framework : isole QBCore / ESX / standalone derriere une API unique.
Framework = {}
local detected = Config.Framework

if detected == 'auto' then
  if GetResourceState('qb-core') == 'started' then detected = 'qbcore'
  elseif GetResourceState('es_extended') == 'started' then detected = 'esx'
  else detected = 'standalone' end
end
Framework.name = detected

local QB, ESX
if detected == 'qbcore' then QB = exports['qb-core']:GetCoreObject()
elseif detected == 'esx' then ESX = exports['es_extended']:getSharedObject() end

function Framework.GetIdentifier(src)
  if detected == 'qbcore' then
    local p = QB.Functions.GetPlayer(src); return p and p.PlayerData.citizenid or nil
  elseif detected == 'esx' then
    local p = ESX.GetPlayerFromId(src); return p and p.identifier or nil
  else
    return GetPlayerIdentifierByType(src, 'license')
  end
end

function Framework.GetJob(src)
  if detected == 'qbcore' then
    local p = QB.Functions.GetPlayer(src); return p and p.PlayerData.job.name or nil
  elseif detected == 'esx' then
    local p = ESX.GetPlayerFromId(src); return p and p.job and p.job.name or nil
  else
    return nil
  end
end

function Framework.Notify(src, msg)
  if detected == 'qbcore' then
    TriggerClientEvent('QBCore:Notify', src, msg, 'primary', 5000)
  elseif detected == 'esx' then
    TriggerClientEvent('esx:showNotification', src, msg)
  else
    TriggerClientEvent('chat:addMessage', src, { args = { '[Agenda]', msg } })
  end
end

function Framework.FindPlayerByCitizen(citizen)
  for _, src in ipairs(GetPlayers()) do
    if Framework.GetIdentifier(src) == citizen then return src end
  end
  return nil
end
