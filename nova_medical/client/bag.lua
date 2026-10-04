-- nova_medical/client/bag.lua
-- Sac médical déployable

local ESX = exports['es_extended']:getSharedObject()

-- Zones actives : [bagId] = { zoneHandle, prop }
local activeBagZones = {}

-- ── Déploiement du sac ────────────────────────────────────────────────────────

local function deployBag()
    local xp = ESX.GetPlayerData()
    if not xp or xp.job.name ~= 'ambulance' then
        lib.notify({ title = 'Accès refusé', description = 'Réservé au personnel EMS.', type = 'error', duration = 2000 })
        return
    end

    local ok = lib.progressBar({
        duration     = 2000,
        label        = 'Déploiement du sac médical...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'anim@amb@business@mcs@mcs_office_what_01', clip = 'mcs_office_what_01_base' },
    })
    if not ok then return end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    TriggerServerEvent('nova_medical:deployBag', pos.x, pos.y, pos.z)
end

-- ── Création de la zone + prop (reçu du serveur) ──────────────────────────────

local function createBagZone(bagId, x, y, z, items)
    if activeBagZones[bagId] then return end  -- déjà créé

    -- Prop visuel (local)
    local prop = nil
    local model = `hei_prop_hei_medkit_01`
    RequestModel(model)
    local t = GetGameTimer()
    while not HasModelLoaded(model) do
        Wait(10)
        if GetGameTimer() - t > 3000 then model = nil; break end
    end
    if model then
        prop = CreateObject(model, x, y, z - 0.05, false, false, false)
        PlaceObjectOnGroundProperly(prop)
        SetEntityAsMissionEntity(prop, true, true)
        SetModelAsNoLongerNeeded(model)
    end

    -- Blip sur le sac
    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 3)
    SetBlipScale(blip, 0.6)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Sac Médical EMS')
    EndTextCommandSetBlipName(blip)

    -- Options ox_target : un par item
    local targetOptions = {}
    for _, slot in ipairs(items) do
        local s = slot  -- capture locale
        table.insert(targetOptions, {
            name        = 'bag_' .. bagId .. '_' .. s.item,
            icon        = 'fas fa-box-open',
            label       = ('%s (×%d)'):format(s.label, s.qty),
            distance    = 2.5,
            canInteract = function() return s.qty > 0 end,
            onSelect    = function()
                TriggerServerEvent('nova_medical:takeBagItem', bagId, s.item)
            end,
        })
    end

    -- Option ramasser (EMS uniquement)
    table.insert(targetOptions, {
        name     = 'bag_' .. bagId .. '_pickup',
        icon     = 'fas fa-shopping-bag',
        label    = 'Récupérer le sac',
        distance = 2.5,
        canInteract = function()
            local xp = ESX.GetPlayerData()
            return xp and xp.job.name == 'ambulance'
        end,
        onSelect = function()
            TriggerServerEvent('nova_medical:pickupBag', bagId)
        end,
    })

    -- Zone sphérique ox_target
    local zone = exports['ox_target']:addSphereZone({
        coords  = vector3(x, y, z),
        radius  = 1.8,
        options = targetOptions,
        debug   = false,
    })

    activeBagZones[bagId] = { zone = zone, prop = prop, blip = blip, items = items }
end

local function removeBagZone(bagId)
    local data = activeBagZones[bagId]
    if not data then return end

    if data.zone  then exports['ox_target']:removeZone(data.zone) end
    if data.prop  then DeleteEntity(data.prop) end
    if data.blip  then RemoveBlip(data.blip) end

    activeBagZones[bagId] = nil
end

local function updateBagStock(bagId, newItems)
    local data = activeBagZones[bagId]
    if not data then return end

    -- Mettre à jour les qtés locales (pour canInteract)
    for _, newSlot in ipairs(newItems) do
        for _, slot in ipairs(data.items) do
            if slot.item == newSlot.item then
                slot.qty = newSlot.qty
            end
        end
    end
    -- Mettre à jour les labels des targets
    for _, newSlot in ipairs(newItems) do
        exports['ox_target']:updateOption(
            'bag_' .. bagId .. '_' .. newSlot.item,
            { label = ('%s (×%d)'):format(newSlot.label, newSlot.qty) }
        )
    end
end

-- ── Évènements serveur ────────────────────────────────────────────────────────

AddEventHandler('nova_medical:bag_deployed', function(bagId, x, y, z, items)
    createBagZone(bagId, x, y, z, items)
end)

AddEventHandler('nova_medical:bag_updated', function(bagId, newItems)
    updateBagStock(bagId, newItems)
end)

AddEventHandler('nova_medical:bag_removed', function(bagId)
    removeBagZone(bagId)
    lib.notify({
        title       = 'Sac médical',
        description = 'Le sac médical a été retiré.',
        type        = 'inform',
        duration    = 3000,
        icon        = 'fas fa-shopping-bag',
    })
end)

-- ── Commande ─────────────────────────────────────────────────────────────────

RegisterCommand('deploybag', function()
    deployBag()
end, false)

lib.addKeybind({
    name        = 'nova_deploybag',
    description = 'Déployer le sac médical EMS',
    defaultKey  = 'B',
    onPressed   = function()
        local xp = ESX.GetPlayerData()
        if xp and xp.job.name == 'ambulance' then
            deployBag()
        end
    end,
})
