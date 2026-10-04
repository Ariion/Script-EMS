-- Acces base (oxmysql). Pas de logique metier ici, juste des requetes.
-- NOTE: oxmysql renvoie les DATETIME en nombre (ms). On force un format texte
-- via DATE_FORMAT pour que le client (JS) et le serveur (Lua) lisent une chaine.
DB = {}

local DTF = "'%Y-%m-%d %H:%i:%s'"  -- format datetime commun

function DB.UpsertBusiness(id, label, btype, job, color)
  MySQL.update.await(
    'INSERT INTO agenda_businesses (id,label,type,job,color) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE label=VALUES(label),type=VALUES(type),job=VALUES(job),color=VALUES(color)',
    { id, label, btype, job, color }
  )
end

function DB.UpsertService(businessId, id, name, duration, price)
  MySQL.update.await(
    'INSERT INTO agenda_services (business_id,id,name,duration,price) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name),duration=VALUES(duration),price=VALUES(price)',
    { businessId, id, name, duration, price }
  )
end

function DB.SlotExists(businessId, serviceId, startTime)
  local r = MySQL.query.await(
    'SELECT id FROM agenda_slots WHERE business_id=? AND service_id=? AND start_time=? LIMIT 1',
    { businessId, serviceId, startTime }
  )
  return r and r[1] ~= nil
end

function DB.CreateSlot(businessId, serviceId, startTime, endTime)
  MySQL.insert.await(
    'INSERT INTO agenda_slots (business_id,service_id,start_time,end_time,status) VALUES (?,?,?,?,?)',
    { businessId, serviceId, startTime, endTime, 'free' }
  )
end

function DB.GetFreeSlots(businessId, serviceId)
  return MySQL.query.await(
    "SELECT id, DATE_FORMAT(start_time, "..DTF..") AS start_time, DATE_FORMAT(end_time, "..DTF..") AS end_time "..
    "FROM agenda_slots WHERE business_id=? AND service_id=? AND status=? AND start_time >= NOW() ORDER BY start_time",
    { businessId, serviceId, 'free' }
  )
end

function DB.IsSlotFree(slotId)
  local r = MySQL.query.await('SELECT status FROM agenda_slots WHERE id=?', { slotId })
  return r and r[1] and r[1].status == 'free'
end

function DB.BookSlot(slotId, citizen)
  MySQL.update.await('UPDATE agenda_slots SET status=? WHERE id=?', { 'booked', slotId })
  return MySQL.insert.await(
    'INSERT INTO agenda_appointments (slot_id, citizen, status) VALUES (?,?,?)',
    { slotId, citizen, 'pending' }
  )
end

function DB.GetTodayAppointments(businessId)
  return MySQL.query.await(
    "SELECT a.id, a.status, a.citizen, "..
    "DATE_FORMAT(s.start_time, "..DTF..") AS start_time, "..
    "DATE_FORMAT(s.end_time, "..DTF..") AS end_time, s.service_id "..
    "FROM agenda_appointments a "..
    "JOIN agenda_slots s ON s.id = a.slot_id "..
    "WHERE s.business_id = ? AND DATE(s.start_time) = CURDATE() "..
    "ORDER BY s.start_time",
    { businessId }
  )
end

function DB.GetAppointmentBusiness(apptId)
  local r = MySQL.query.await(
    'SELECT s.business_id FROM agenda_appointments a JOIN agenda_slots s ON s.id = a.slot_id WHERE a.id = ? LIMIT 1',
    { apptId }
  )
  return r and r[1] and r[1].business_id
end

function DB.SetAppointmentStatus(apptId, status)
  MySQL.update.await('UPDATE agenda_appointments SET status=? WHERE id=?', { status, apptId })
end

function DB.GetMyAppointments(citizen)
  return MySQL.query.await(
    "SELECT a.id, a.status, DATE_FORMAT(s.start_time, "..DTF..") AS start_time, s.business_id, s.service_id "..
    "FROM agenda_appointments a "..
    "JOIN agenda_slots s ON a.slot_id = s.id "..
    "WHERE a.citizen = ? AND s.start_time >= NOW() AND a.status IN ('pending','confirmed') "..
    "ORDER BY s.start_time",
    { citizen }
  )
end

function DB.GetAppointmentDetails(apptId)
  local r = MySQL.query.await(
    "SELECT a.citizen, s.business_id, s.service_id, DATE_FORMAT(s.start_time, "..DTF..") AS start_time, a.slot_id "..
    "FROM agenda_appointments a "..
    "JOIN agenda_slots s ON a.slot_id = s.id "..
    "WHERE a.id = ? LIMIT 1",
    { apptId }
  )
  return r and r[1] or nil
end

function DB.GetSlot(slotId)
  local r = MySQL.query.await(
    "SELECT id, business_id, service_id, DATE_FORMAT(start_time, "..DTF..") AS start_time "..
    "FROM agenda_slots WHERE id=? LIMIT 1",
    { slotId }
  )
  return r and r[1] or nil
end

function DB.GetUpcomingReminders(minutesBefore)
  return MySQL.query.await(
    "SELECT a.id, a.citizen, DATE_FORMAT(s.start_time, "..DTF..") AS start_time, s.service_id, s.business_id "..
    "FROM agenda_appointments a "..
    "JOIN agenda_slots s ON a.slot_id = s.id "..
    "WHERE a.status IN ('pending','confirmed') "..
    "AND s.start_time BETWEEN DATE_ADD(NOW(), INTERVAL ? MINUTE) AND DATE_ADD(NOW(), INTERVAL ? MINUTE)",
    { minutesBefore - 1, minutesBefore + 1 }
  )
end

function DB.CancelAppointment(apptId, slotId)
  MySQL.update.await('UPDATE agenda_appointments SET status=? WHERE id=?', { 'cancelled', apptId })
  MySQL.update.await('UPDATE agenda_slots SET status=? WHERE id=?', { 'free', slotId })
end