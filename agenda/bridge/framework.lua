-- Pont framework (SERVEUR) : isole QBCore / ESX / standalone derrière une API unique.
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

local npwdActive = GetResourceState('npwd') == 'started'

-- ── Identifiants ─────────────────────────────────────────────────────

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

-- ── Notifications ─────────────────────────────────────────────────────
-- Si NPWD est actif, la notif apparaît dans le téléphone in-game.
-- Sinon fallback framework classique.

function Framework.Notify(src, msg)
  if npwdActive then
    pcall(function()
      exports['npwd']:addNotification(src, {
        app           = 'MESSAGES',
        title         = 'Agenda',
        content       = msg,
        keepOpen      = false,
        phoneNotification = true,
      })
    end)
    -- On envoie aussi une notif texte légère en parallèle
    if detected == 'esx' then
      TriggerClientEvent('esx:showNotification', src, '📅 ' .. msg)
    end
    return
  end
  -- Fallback sans NPWD
  if detected == 'qbcore' then
    TriggerClientEvent('QBCore:Notify', src, msg, 'primary', 5000)
  elseif detected == 'esx' then
    TriggerClientEvent('esx:showNotification', src, msg)
  else
    TriggerClientEvent('chat:addMessage', src, { args = { '[Agenda]', msg } })
  end
end

-- ── Recherche joueur par identifiant ─────────────────────────────────

function Framework.FindPlayerByCitizen(citizen)
  for _, src in ipairs(GetPlayers()) do
    if Framework.GetIdentifier(tonumber(src)) == citizen then return tonumber(src) end
  end
  return nil
end

-- ── NPWD : cycle de vie joueur ────────────────────────────────────────
-- Enregistre / décharge le joueur dans NPWD quand il se connecte / déconnecte.

if npwdActive then
  local function npwdRegisterPlayer(src)
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return end
    -- Numéro de téléphone généré à partir de l'id serveur (remplacer par DB si souhaité)
    local phoneNumber = tostring(5550000 + src)
    local firstname, lastname = 'Joueur', tostring(src)
    if detected == 'esx' then
      local p = ESX.GetPlayerFromId(src)
      if p then
        firstname = p.get('firstName') or p.getName() or firstname
        lastname  = p.get('lastName') or ''
      end
    elseif detected == 'qbcore' then
      local p = QB.Functions.GetPlayer(src)
      if p then
        firstname = p.PlayerData.charinfo and p.PlayerData.charinfo.firstname or firstname
        lastname  = p.PlayerData.charinfo and p.PlayerData.charinfo.lastname  or ''
      end
    end
    pcall(function()
      exports['npwd']:newPlayer({
        source      = src,
        identifier  = identifier,
        phoneNumber = phoneNumber,
        firstname   = firstname,
        lastname    = lastname,
      })
    end)
  end

  -- ESX
  AddEventHandler('esx:playerLoaded', function(playerId)
    CreateThread(function()
      Wait(1000) -- laisser le temps au framework de charger
      npwdRegisterPlayer(playerId)
    end)
  end)

  AddEventHandler('esx:playerDropped', function(playerId)
    pcall(function() exports['npwd']:unloadPlayer(playerId) end)
  end)

  -- QBCore
  AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    CreateThread(function()
      Wait(1000)
      npwdRegisterPlayer(Player.PlayerData.source)
    end)
  end)

  AddEventHandler('QBCore:Server:PlayerDropped', function(src)
    pcall(function() exports['npwd']:unloadPlayer(src) end)
  end)

  -- Standalone / fallback
  AddEventHandler('playerConnecting', function()
    local src = source
    CreateThread(function()
      Wait(3000)
      npwdRegisterPlayer(src)
    end)
  end)
end
