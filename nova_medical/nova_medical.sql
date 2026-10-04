-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Migration SQL
--  À exécuter dans HeidiSQL sur votre base FiveM (ex: essentialmode)
-- ═══════════════════════════════════════════════════════════════

-- Table principale : données médicales persistantes par joueur
CREATE TABLE IF NOT EXISTS `nova_medical_data` (
    `identifier`  VARCHAR(60)   NOT NULL,
    `injuries`    LONGTEXT      DEFAULT NULL COMMENT 'JSON : { head:[...], torso:[...], ... }',
    `diseases`    LONGTEXT      DEFAULT NULL COMMENT 'JSON : { infection:{severity:1.2}, ... }',
    `updated_at`  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`),
    KEY `idx_updated` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Items médicaux à ajouter dans votre table items ──────────────
-- (adaptez le nom de la table si ce n'est pas "items")
-- Ces INSERT sont en mode IGNORE pour ne pas écraser si déjà présent.

INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
('bandage',       'Bandage',                 200,  0, 1),
('tourniquet',    'Garrot hémostatique',     300,  0, 1),
('kit_medical',   'Kit médical',             800,  0, 1),
('morphine',      'Morphine',                150,  1, 1),
('defibrillateur','Défibrillateur',          1200, 1, 1),
('painkillers',   'Antidouleurs',            100,  0, 1),
('splint',        'Attelle',                 500,  0, 1),
('oxygen_mask',   'Masque à oxygène',        400,  0, 1),
('sac_medical',   'Sac médical EMS',         2000, 1, 1);

-- ── Vérification ──────────────────────────────────────────────────
SELECT 'nova_medical_data table OK' AS status;
SELECT COUNT(*) AS items_medicaux FROM `items`
WHERE name IN ('bandage','tourniquet','kit_medical','morphine','defibrillateur','painkillers','splint','oxygen_mask','sac_medical');
