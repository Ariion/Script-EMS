-- AGENDA : schéma complet — généré depuis l'audit des requêtes oxmysql de server/db.lua

-- Entreprises (sync depuis Config.Businesses au démarrage)
CREATE TABLE IF NOT EXISTS `agenda_businesses` (
  `id`    VARCHAR(40)  NOT NULL,
  `label` VARCHAR(80)  NOT NULL,
  `type`  VARCHAR(40)  NOT NULL,
  `job`   VARCHAR(40)  DEFAULT NULL,
  `color` VARCHAR(12)  NOT NULL DEFAULT '#0aa4c4',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Services rattachés à une entreprise (sync depuis Config.Businesses au démarrage)
CREATE TABLE IF NOT EXISTS `agenda_services` (
  `business_id` VARCHAR(40) NOT NULL,
  `id`          VARCHAR(40) NOT NULL,
  `name`        VARCHAR(80) NOT NULL,
  `duration`    INT         NOT NULL DEFAULT 15,
  `price`       INT         NOT NULL DEFAULT 0,
  PRIMARY KEY (`business_id`, `id`),
  CONSTRAINT `fk_services_business`
    FOREIGN KEY (`business_id`) REFERENCES `agenda_businesses` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Créneaux générés par GenerateSlots()
-- Statuts utilisés : 'free' (CreateSlot), 'booked' (BookSlot), remis à 'free' (CancelAppointment)
CREATE TABLE IF NOT EXISTS `agenda_slots` (
  `id`          INT          NOT NULL AUTO_INCREMENT,
  `business_id` VARCHAR(40)  NOT NULL,
  `service_id`  VARCHAR(40)  NOT NULL,
  `start_time`  DATETIME     NOT NULL,
  `end_time`    DATETIME     NOT NULL,
  `status`      ENUM('free','booked') NOT NULL DEFAULT 'free',
  PRIMARY KEY (`id`),
  -- Couvre GetFreeSlots (business_id, service_id, status) + ORDER BY start_time
  -- et SlotExists (business_id, service_id, start_time)
  INDEX `idx_slots_lookup` (`business_id`, `service_id`, `status`, `start_time`),
  -- Couvre GetUpcomingReminders (start_time BETWEEN ...) et GetTodayAppointments (DATE(start_time))
  INDEX `idx_slots_start`  (`start_time`),
  CONSTRAINT `fk_slots_service`
    FOREIGN KEY (`business_id`, `service_id`)
    REFERENCES `agenda_services` (`business_id`, `id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Rendez-vous pris par les joueurs
-- Statuts utilisés : 'pending' (BookSlot), 'confirmed', 'done', 'noshow' (SetAppointmentStatus),
--                    'cancelled' (CancelAppointment)
CREATE TABLE IF NOT EXISTS `agenda_appointments` (
  `id`         INT         NOT NULL AUTO_INCREMENT,
  `slot_id`    INT         NOT NULL,
  `citizen`    VARCHAR(80) NOT NULL,
  `status`     ENUM('pending','confirmed','done','cancelled','noshow') NOT NULL DEFAULT 'pending',
  `created_at` DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  -- Couvre GetMyAppointments et GetUpcomingReminders (WHERE citizen = ?)
  INDEX `idx_appt_citizen` (`citizen`),
  -- Couvre les filtres WHERE status IN ('pending','confirmed')
  INDEX `idx_appt_status`  (`status`),
  CONSTRAINT `fk_appt_slot`
    FOREIGN KEY (`slot_id`) REFERENCES `agenda_slots` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
