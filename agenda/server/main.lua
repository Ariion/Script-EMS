-- AUTORITE serveur : tout se valide ici. Ne jamais croire le client.

local function HexColorToInt(hex)
  if not hex or hex == '' then return 5793266 end
  return tonumber((hex:gsub('#', '')), 16) or 5793266
end

local function SendWebhook(title, fields, color)
  if not Config.Webhook or Config.Webhook == '' then return end
  local payload = json.encode({
    embeds = {{
      title     = title,
      color     = color or 5793266,
      fields    = fields,
      timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
      footer    = { text = 'Agenda' },
    }}
  })
  PerformHttpRequest(Config.Webhook, function() end, 'POST', payload,
    { ['Content-Type'] = 'application/json' })
end

local function GetServiceName(businessId, serviceId)
  local b = Config.Businesses[businessId]
  if not b then return serviceId end
  for _, s in ipairs(b.services or {}) do
    if s.id == serviceId then return s.name end
  end
  return serviceId
end

local function NotifyStaff(businessJob, svcName, timeStr)
  local msg = 'Nouveau RDV : ' .. svcName .. ' a ' .. timeStr
  for _, pid in ipairs(GetPlayers()) do
    local src = tonumber(pid)
    if src and Framework.GetJob(src) == businessJob then
      Framework.Notify(src, msg)
    end
  end
end

local reminded = {}

local function CheckReminders()
  local minutes = Config.ReminderMinutes or 10
  local rows    = DB.GetUpcomingReminders(minutes)
  if not rows then return end
  for _, row in ipairs(rows) do
    if not reminded[row.id] then
      reminded[row.id] = true
      local src = Framework.FindPlayerByCitizen(row.citizen)
      if src then
        local svcName = GetServiceName(row.business_id, row.service_id)
        local timeStr = tostring(row.start_time):sub(12, 16)
        Framework.Notify(src, 'Rappel : votre RDV pour ' .. svcName .. ' commence dans ' .. minutes .. ' min (' .. timeStr .. ').')
      end
    end
  end
end

CreateThread(function()
  while true do
    Wait(60000)
    CheckReminders()
  end
end)

local function SyncConfig()
  for businessId, business in pairs(Config.Businesses) do
    DB.UpsertBusiness(businessId, business.label, business.type, business.job or '', business.color or '#0aa4c4')
    for _, svc in ipairs(business.services) do
      DB.UpsertService(businessId, svc.id, svc.name, svc.duration, svc.price)
    end
  end
end

local function GenerateSlots()
  local now = os.time()
  for dayOffset = 0, 6 do
    local dayTs = now + dayOffset * 86400
    local d     = os.date('*t', dayTs)
    for businessId, business in pairs(Config.Businesses) do
      for _, svc in ipairs(business.services) do
        local slotTs  = os.time({ year=d.year, month=d.month, day=d.day, hour=Config.OpenHour,  min=0, sec=0, isdst=d.isdst })
        local closeTs = os.time({ year=d.year, month=d.month, day=d.day, hour=Config.CloseHour, min=0, sec=0, isdst=d.isdst })
        while slotTs + svc.duration * 60 <= closeTs do
          local startStr = os.date('%Y-%m-%d %H:%M:%S', slotTs)
          local endStr   = os.date('%Y-%m-%d %H:%M:%S', slotTs + svc.duration * 60)
          if not DB.SlotExists(businessId, svc.id, startStr) then
            DB.CreateSlot(businessId, svc.id, startStr, endStr)
          end
          slotTs = slotTs + svc.duration * 60
        end
      end
    end
  end
end

AddEventHandler('onResourceStart', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  SyncConfig()
  GenerateSlots()
  print('[Agenda] Synchronisation et génération des créneaux terminées.')
end)

RegisterCommand('agenda_gen', function(src, args, raw)
  if src ~= 0 and not IsPlayerAceAllowed(src, 'command.agenda_gen') then return end
  GenerateSlots()
  print('[Agenda] Créneaux régénérés via /agenda_gen.')
  if src ~= 0 then
    TriggerClientEvent('chat:addMessage', src, { args = {'[Agenda]', 'Créneaux régénérés.'} })
  end
end, true)

local function GetStaffBusiness(src)
  local job = Framework.GetJob(src)
  if not job then return nil end
  for businessId, business in pairs(Config.Businesses) do
    if business.job == job then return businessId end
  end
  return nil
end

local handlers = {}

handlers['agenda:getSlots'] = function(src, data)
  local b = Config.Businesses[data.businessId]
  if not b then return { ok = false, error = 'business_inconnu' } end
  return { ok = true, slots = DB.GetFreeSlots(data.businessId, data.serviceId) }
end

handlers['agenda:getStaffContext'] = function(src, data)
  local businessId = GetStaffBusiness(src)
  if not businessId then return { ok = true, businessId = nil } end
  return { ok = true, businessId = businessId, label = Config.Businesses[businessId].label }
end

handlers['agenda:getStaffAppointments'] = function(src, data)
  local businessId = GetStaffBusiness(src)
  if not businessId then return { ok = false, error = 'non_autorise' } end
  return { ok = true, appointments = DB.GetTodayAppointments(businessId) }
end

handlers['agenda:setAppointmentStatus'] = function(src, data)
  if not data.apptId or not data.status then return { ok = false, error = 'donnees_invalides' } end
  local allowed = { done = true, noshow = true }
  if not allowed[data.status] then return { ok = false, error = 'statut_invalide' } end
  local businessId = DB.GetAppointmentBusiness(data.apptId)
  if not businessId or GetStaffBusiness(src) ~= businessId then
    return { ok = false, error = 'non_autorise' }
  end
  DB.SetAppointmentStatus(data.apptId, data.status)
  return { ok = true }
end

handlers['agenda:getMyAppointments'] = function(src, data)
  local citizen = Framework.GetIdentifier(src)
  if not citizen then return { ok = false, error = 'joueur_introuvable' } end
  return { ok = true, appointments = DB.GetMyAppointments(citizen) }
end

handlers['agenda:cancelAppointment'] = function(src, data)
  if not data.apptId then return { ok = false, error = 'parametre_invalide' } end
  local citizen = Framework.GetIdentifier(src)
  if not citizen then return { ok = false, error = 'joueur_introuvable' } end
  local details = DB.GetAppointmentDetails(data.apptId)
  if not details or details.citizen ~= citizen then
    return { ok = false, error = 'non_autorise' }
  end
  DB.CancelAppointment(data.apptId, details.slot_id)
  local b = Config.Businesses[details.business_id]
  SendWebhook('Reservation annulee', {
    { name = 'Entreprise', value = b and b.label or details.business_id,                    inline = true  },
    { name = 'Service',    value = GetServiceName(details.business_id, details.service_id), inline = true  },
    { name = 'Creneau',    value = tostring(details.start_time):sub(1, 16),                 inline = false },
    { name = 'Joueur',     value = citizen,                                                 inline = false },
  }, HexColorToInt(b and b.color or ''))
  return { ok = true }
end

handlers['agenda:book'] = function(src, data)
  local citizen = Framework.GetIdentifier(src)
  if not citizen then return { ok = false, error = 'joueur_introuvable' } end
  if not DB.IsSlotFree(data.slotId) then
    return { ok = false, error = 'creneau_pris' }
  end
  local slot   = DB.GetSlot(data.slotId)
  local apptId = DB.BookSlot(data.slotId, citizen)
  if slot then
    local b       = Config.Businesses[slot.business_id]
    local svcName = GetServiceName(slot.business_id, slot.service_id)
    local timeStr = tostring(slot.start_time):sub(12, 16)
    if b and b.job then NotifyStaff(b.job, svcName, timeStr) end
    SendWebhook('Nouvelle reservation', {
      { name = 'Entreprise', value = b and b.label or slot.business_id,    inline = true  },
      { name = 'Service',    value = svcName,                              inline = true  },
      { name = 'Creneau',    value = tostring(slot.start_time):sub(1, 16), inline = false },
      { name = 'Joueur',     value = citizen,                              inline = false },
    }, HexColorToInt(b and b.color or ''))
  end
  return { ok = true, appointmentId = apptId }
end

RegisterNetEvent('agenda:request', function(name, reqId, data)
  local src = source
  local fn = handlers[name]
  local result = fn and fn(src, data) or { ok = false, error = 'action_inconnue' }
  TriggerClientEvent('agenda:response', src, reqId, result)
end)
