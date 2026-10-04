-- ═══════════════════════════════════════════════════════════════
--  nova_medical — Configuration centrale
-- ═══════════════════════════════════════════════════════════════

MedConfig = {}

-- ── Job EMS ──────────────────────────────────────────────────────
MedConfig.EmsJob = 'ambulance'

-- ── Zones corporelles ────────────────────────────────────────────
MedConfig.BodyZones = {
    head     = { label = 'Tête / Cou',      short = 'Tête'    },
    torso    = { label = 'Torse / Abdomen', short = 'Torse'   },
    leftArm  = { label = 'Bras Gauche',     short = 'Bras G.' },
    rightArm = { label = 'Bras Droit',      short = 'Bras D.' },
    leftLeg  = { label = 'Jambe Gauche',    short = 'Jambe G.'},
    rightLeg = { label = 'Jambe Droite',    short = 'Jambe D.'},
}

-- ── Types de blessures ───────────────────────────────────────────
MedConfig.InjuryTypes = {
    gunshot    = { label = 'Plaie par balle',         bleed = true,  severe = true  },
    stab       = { label = 'Plaie par arme blanche',  bleed = true,  severe = false },
    bruise     = { label = 'Contusion',               bleed = false, severe = false },
    fracture   = { label = 'Fracture',                bleed = false, severe = true  },
    sprain     = { label = 'Entorse',                 bleed = false, severe = false },
    burn       = { label = 'Brûlure',                 bleed = false, severe = true  },
    explosion  = { label = 'Traumatisme d\'explosion',bleed = true,  severe = true  },
    laceration = { label = 'Lacération',              bleed = true,  severe = false },
    concussion = { label = 'Commotion cérébrale',     bleed = false, severe = true  },
    blunt      = { label = 'Traumatisme contondant',  bleed = false, severe = false },
    internal   = { label = 'Hémorragie interne',      bleed = true,  severe = true  },
}

-- ── Debuffs par zone (selon sévérité seuil) ──────────────────────
--  threshold : sévérité minimale pour déclencher
--  chance    : % de déclenchement (pour ragdoll etc.)
MedConfig.ZoneDebuffs = {
    head = {
        { type = 'cameraShake', threshold = 2, intensity = 0.10 },   -- seuil relevé, intensité réduite
        { type = 'visionBlur',  threshold = 3 },                     -- seulement si grave
        { type = 'drunk',       threshold = 4 },
        { type = 'noSprint',    threshold = 5 },
    },
    torso = {
        { type = 'bleed',       threshold = 2 },                     -- saignement à partir de sév 2
        { type = 'ragdoll',     threshold = 3, chance = 5 },         -- chance réduite
        { type = 'noSprint',    threshold = 4 },
        { type = 'staminaDrain',threshold = 3 },
    },
    leftArm = {
        { type = 'aimShake',    threshold = 2, intensity = 0.08 },
        { type = 'reducedGrip', threshold = 3 },
        { type = 'noShoot',     threshold = 5 },
    },
    rightArm = {
        { type = 'aimShake',    threshold = 2, intensity = 0.08 },
        { type = 'reducedGrip', threshold = 3 },
        { type = 'noShoot',     threshold = 5 },
    },
    leftLeg = {
        { type = 'moveSlow',    threshold = 1, factor = 0.85 },      -- ralentissement léger
        { type = 'limp',        threshold = 2 },                     -- boiterie à partir de sév 2
        { type = 'noSprint',    threshold = 3 },
        { type = 'noJump',      threshold = 3 },
        { type = 'noDrive',     threshold = 4 },                     -- plus de conduite si critique
        { type = 'ragdoll',     threshold = 4, chance = 5 },
    },
    rightLeg = {
        { type = 'moveSlow',    threshold = 1, factor = 0.85 },
        { type = 'limp',        threshold = 2 },
        { type = 'noSprint',    threshold = 3 },
        { type = 'noJump',      threshold = 3 },
        { type = 'noDrive',     threshold = 4 },
        { type = 'ragdoll',     threshold = 4, chance = 5 },
    },
}

-- ── Items de soin ─────────────────────────────────────────────────
--  heals    : types de blessures soignées ('any' = toutes)
--  zones    : zones traitables ('any' = toutes)
--  severity : points de sévérité retirés
--  bleed    : stoppe le saignement
--  revive   : peut réanimer
--  painKill : réduit les debuffs temporairement (30s)
--  emsOnly  : réservé EMS
MedConfig.HealingItems = {
    bandage = {
        label    = 'Bandage',
        duration = 5000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = { 'laceration', 'stab', 'gunshot' },
        zones    = { 'any' },
        severity = 1,
        bleed    = true,
    },
    tourniquet = {
        label    = 'Garrot hémostatique',
        duration = 8000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = { 'gunshot', 'laceration', 'stab' },
        zones    = { 'leftArm', 'rightArm', 'leftLeg', 'rightLeg' },
        severity = 2,
        bleed    = true,
    },
    kit_medical = {
        label    = 'Kit médical',
        duration = 12000,
        anim     = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
        heals    = { 'any' },
        zones    = { 'any' },
        severity = 2,
        bleed    = true,
    },
    morphine = {
        label    = 'Morphine',
        duration = 6000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = {},
        zones    = { 'any' },
        severity = 0,
        painKill = true,
    },
    defibrillateur = {
        label    = 'Défibrillateur',
        duration = 8000,
        anim     = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
        heals    = {},
        zones    = { 'any' },
        severity = 0,
        revive   = true,
        emsOnly  = true,
    },
    painkillers = {
        label    = 'Antidouleurs',
        duration = 4000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = { 'bruise', 'sprain', 'blunt' },
        zones    = { 'any' },
        severity = 1,
        painKill = true,
    },
    splint = {
        label    = 'Attelle',
        duration = 10000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = { 'fracture', 'sprain' },
        zones    = { 'leftArm', 'rightArm', 'leftLeg', 'rightLeg' },
        severity = 2,
    },
    oxygen_mask = {
        label    = 'Masque à oxygène',
        duration = 6000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = {},
        zones    = { 'any' },
        severity = 0,
        oxygen   = true,
    },
    sac_medical = {
        label    = 'Sac médical EMS',
        duration = 15000,
        anim     = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
        heals    = { 'any' },
        zones    = { 'any' },
        severity = 4,
        bleed    = true,
        emsOnly  = true,
    },
    perfusion_iv = {
        label    = 'Perfusion IV',
        duration = 18000,
        anim     = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
        heals    = { 'internal', 'explosion', 'gunshot' },
        zones    = { 'any' },
        severity = 3,
        bleed    = true,
        oxygen   = true,
        emsOnly  = true,
    },
    collar_cervical = {
        label    = 'Collier cervical',
        duration = 7000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = { 'fracture', 'concussion', 'blunt' },
        zones    = { 'head', 'torso' },
        severity = 2,
        emsOnly  = true,
    },
    epi_pen = {
        label    = 'Stylo-auto adrénaline',
        duration = 4000,
        anim     = { dict = 'mp_suicide', clip = 'pill' },
        heals    = {},
        zones    = { 'any' },
        severity = 0,
        revive   = true,
        painKill = true,
        emsOnly  = true,
    },
}

-- ── Examens diagnostiques ─────────────────────────────────────────
MedConfig.Exams = {
    { id = 'initial',      label = 'Évaluation initiale', icon = '🔍', duration = 3000  },
    { id = 'bp',           label = 'Tension artérielle',  icon = '💓', duration = 5000  },
    { id = 'spo2',         label = 'Saturation O₂',       icon = '🫁', duration = 4000  },
    { id = 'neuro',        label = 'Bilan neurologique',  icon = '🧠', duration = 6000  },
    { id = 'ecg',          label = 'ECG',                 icon = '📈', duration = 8000  },
    { id = 'auscultation', label = 'Auscultation',        icon = '🩺', duration = 5000  },
    { id = 'glucose',      label = 'Glycémie',            icon = '🩸', duration = 4000  },
    { id = 'temp',         label = 'Température',         icon = '🌡️', duration = 3000  },
}

-- ── Maladies ──────────────────────────────────────────────────────
MedConfig.Diseases = {
    infection    = { label = 'Infection',            chronic = false, tickSev = 0.08, maxSev = 5.0 },
    sepsis       = { label = 'Septicémie',           chronic = false, tickSev = 0.15, maxSev = 5.0 },
    pneumothorax = { label = 'Pneumothorax',         chronic = false, tickSev = 0.10, maxSev = 5.0 },
    concussion   = { label = 'Commotion cérébrale',  chronic = false, tickSev = 0.05, maxSev = 5.0 },
    overdose     = { label = 'Overdose',             chronic = false, tickSev = 0.12, maxSev = 5.0 },
    hypothermia  = { label = 'Hypothermie',          chronic = false, tickSev = 0.07, maxSev = 5.0 },
    diabetes     = { label = 'Diabète',              chronic = true,  tickSev = 0.03, maxSev = 5.0 },
    hypertension = { label = 'Hypertension',         chronic = true,  tickSev = 0.04, maxSev = 5.0 },
    asthma       = { label = 'Asthme',               chronic = true,  tickSev = 0.05, maxSev = 5.0 },
    arrhythmia   = { label = 'Arythmie',             chronic = true,  tickSev = 0.04, maxSev = 5.0 },
}

-- ── Mort & réanimation ────────────────────────────────────────────
MedConfig.Death = {
    lastStandTime  = 480,    -- 8 min avant mort définitive (augmenté pour laisser le temps à l'EMS)
    bleedDamage    = 1,      -- dégâts santé/tick (tick toutes les 5s côté serveur)
    reviveDistance = 6.0,    -- distance max pour réanimer
    respawnDelay   = 20,     -- secondes d'attente avant pouvoir respawn (réduit)
    respawnCost    = 1500,   -- coût de respawn en $
    -- Taux de réussite utilisés dans nova_medical:heal (revive=true)
    -- CPR sans item : 75% (géré directement dans nova_medical:cpr)
    reviveOptions  = {
        { item = 'defibrillateur', label = 'Défibrillateur', duration = 9000,  successChance = 95 },
        { item = 'kit_medical',    label = 'CPR + Kit',       duration = 14000, successChance = 75 },
        { item = 'morphine',       label = 'Adrénaline',      duration = 6000,  successChance = 55 },
    },
}

-- ── Détection armes → blessures ───────────────────────────────────
-- Mappage hash d'arme → type de blessure
MedConfig.WeaponInjuryMap = {
    -- Armes à feu → gunshot
    ['WEAPON_PISTOL']          = 'gunshot',
    ['WEAPON_PISTOL50']        = 'gunshot',
    ['WEAPON_COMBATPISTOL']    = 'gunshot',
    ['WEAPON_SMG']             = 'gunshot',
    ['WEAPON_ASSAULTRIFLE']    = 'gunshot',
    ['WEAPON_CARBINERIFLE']    = 'gunshot',
    ['WEAPON_SNIPERRIFLE']     = 'gunshot',
    ['WEAPON_SHOTGUN']         = 'gunshot',
    -- Armes blanches → stab/blunt
    ['WEAPON_KNIFE']           = 'stab',
    ['WEAPON_SWITCHBLADE']     = 'stab',
    ['WEAPON_MACHETE']         = 'stab',
    ['WEAPON_BAT']             = 'blunt',
    ['WEAPON_CROWBAR']         = 'blunt',
    ['WEAPON_HAMMER']          = 'blunt',
    ['WEAPON_UNARMED']         = 'bruise',
    -- Explosifs → explosion
    ['WEAPON_GRENADE']         = 'explosion',
    ['WEAPON_RPGLAUNCHER']     = 'explosion',
    ['WEAPON_STICKYBOMB']      = 'explosion',
}

-- ── Sac médical déployable ────────────────────────────────────────
-- Stock de départ quand un EMS déploie son sac (item → quantité)
MedConfig.BagStock = {
    bandage    = { label = 'Bandage',              qty = 8  },
    tourniquet = { label = 'Garrot hémostatique',  qty = 4  },
    kit_medical= { label = 'Kit médical',           qty = 3  },
    painkillers= { label = 'Antidouleurs',          qty = 6  },
    splint     = { label = 'Attelle',               qty = 3  },
    oxygen_mask= { label = 'Masque à oxygène',      qty = 2  },
    morphine   = { label = 'Morphine',              qty = 2  },
}

-- ── Protocoles de soins ───────────────────────────────────────────
MedConfig.Protocols = {
    {
        id    = 'abcde',
        label = 'Bilan ABCDE',
        icon  = '📋',
        steps = {
            { id='A', label='Airways — Voies aériennes', icon='🫁', examId='auscultation', hint='Vérifier la liberté des voies aériennes' },
            { id='B', label='Breathing — Respiration',   icon='💨', examId='spo2',         hint='Évaluer la ventilation et la SpO₂' },
            { id='C', label='Circulation',              icon='💓', examId='bp',           hint='Bilan circulatoire, pouls et PA' },
            { id='D', label='Disability — Neuro',       icon='🧠', examId='neuro',        hint='Score GCS et réactivité pupillaire' },
            { id='E', label='Exposure — Exposition',    icon='🔍', examId='initial',      hint='Bilan lésionnel complet' },
        },
    },
    {
        id    = 'poly_trauma',
        label = 'Polytraumatisme',
        icon  = '🚑',
        steps = {
            { id='1', label='Contrôle hémorragies',    icon='🩸', examId='initial',  hint='Arrêter les saignements actifs' },
            { id='2', label='Liberté voies aériennes', icon='🫁', examId='spo2',     hint='Intubation si nécessaire' },
            { id='3', label='Bilan hémodynamique',     icon='💓', examId='bp',       hint='Tension artérielle et FC' },
            { id='4', label='ECG de contrôle',         icon='📈', examId='ecg',      hint='Rechercher trouble du rythme' },
            { id='5', label='Bilan neurologique',      icon='🧠', examId='neuro',    hint='GCS et score de Glasgow' },
            { id='6', label='Glycémie + température',  icon='🌡️', examId='glucose',  hint='Paramètres biologiques rapides' },
        },
    },
    {
        id    = 'cardiac',
        label = 'Arrêt cardiaque',
        icon  = '❤️',
        steps = {
            { id='1', label='Confirmation arrêt',       icon='💀', examId='initial', hint='Absence de pouls et de conscience' },
            { id='2', label='ECG — Rythme choquable ?', icon='📈', examId='ecg',    hint='FV ou TV → défibrillation' },
            { id='3', label='Ventilation assistée',     icon='🫁', examId='spo2',   hint='Vérifier la ventilation assistée' },
            { id='4', label='Bilan post-réanimation',   icon='🧠', examId='neuro',  hint='GCS et déficit neurologique' },
        },
    },
}

-- ── Zone touchée selon os GTA (PedBoneId)
MedConfig.BoneZoneMap = {
    [31086] = 'head',     -- SKEL_Head
    [6286]  = 'head',     -- SKEL_Neck_1
    [24818] = 'torso',    -- SKEL_Spine_Root
    [11816] = 'torso',    -- SKEL_Spine2
    [14201] = 'torso',    -- SKEL_L_Clavicle
    [52301] = 'torso',    -- SKEL_R_Clavicle
    [40269] = 'leftArm',  -- SKEL_L_UpperArm
    [58271] = 'leftArm',  -- SKEL_L_Forearm
    [36029] = 'rightArm', -- SKEL_R_UpperArm
    [61163] = 'rightArm', -- SKEL_R_Forearm
    [51826] = 'leftLeg',  -- SKEL_L_Thigh
    [63931] = 'leftLeg',  -- SKEL_L_Calf
    [36864] = 'rightLeg', -- SKEL_R_Thigh
    [16335] = 'rightLeg', -- SKEL_R_Calf
}
