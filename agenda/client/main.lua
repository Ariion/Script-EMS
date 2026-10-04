-- Cote client : ouvre l'UI et relaie les actions vers le serveur.
RegisterCommand('agenda', function() Phone.OpenApp() end, false)

RegisterNUICallback('close', function(_, cb)
  SetNuiFocus(false, false); cb({})
end)

RegisterNUICallback('getSlots', function(data, cb)
  QBCallbackLike('agenda:getSlots', function(result) cb(result) end, data)
end)

RegisterNUICallback('book', function(data, cb)
  QBCallbackLike('agenda:book', function(result) cb(result) end, data)
end)

RegisterNUICallback('getStaffContext', function(data, cb)
  QBCallbackLike('agenda:getStaffContext', function(result) cb(result) end, data)
end)

RegisterNUICallback('getStaffAppointments', function(data, cb)
  QBCallbackLike('agenda:getStaffAppointments', function(result) cb(result) end, data)
end)

RegisterNUICallback('setAppointmentStatus', function(data, cb)
  QBCallbackLike('agenda:setAppointmentStatus', function(result) cb(result) end, data)
end)

RegisterNUICallback('getMyAppointments', function(data, cb)
  QBCallbackLike('agenda:getMyAppointments', function(result) cb(result) end, data)
end)

RegisterNUICallback('cancelAppointment', function(data, cb)
  QBCallbackLike('agenda:cancelAppointment', function(result) cb(result) end, data)
end)

local pending, reqId = {}, 0
function QBCallbackLike(name, cb, data)
  reqId = reqId + 1; pending[reqId] = cb
  TriggerServerEvent('agenda:request', name, reqId, data)
end
RegisterNetEvent('agenda:response', function(id, result)
  if pending[id] then pending[id](result); pending[id] = nil end
end)
