/* ═══════════════════════════════════════════════════
   NOVA MEDICAL — UI Script
   OMC · ESX · FiveM
═══════════════════════════════════════════════════ */

'use strict';

// ── Données globales ──────────────────────────────
let currentMedical  = null;
let currentPatient  = '';
let sessionStart    = null;
let timerInterval   = null;
let lastStandEnd    = null;
let lsInterval      = null;
let respawnDelay    = 0;
let respawnUnlock   = null;
let respawnInterval = null;
let isEmsMode       = false;

// ── NUI Message handler ───────────────────────────
window.addEventListener('message', (event) => {
  const d = event.data;
  if (!d || !d.action) return;

  switch (d.action) {
    case 'openSelf':
    case 'openExam':
      openMedical(d);
      break;
    case 'hideUI':
      closeAll();
      break;
    case 'lastStand':
      showLastStand(d.duration);
      break;
    case 'showDeath':
      showDeath(d.respawnDelay || 0);
      break;
    case 'examLoading': {
      const btn = document.querySelector(`.exam-btn[data-exam="${d.examId}"]`);
      if (btn) {
        btn.classList.add('loading');
        btn.disabled = true;
        const orig = btn.textContent;
        btn.textContent = '⏳ En cours...';
        setTimeout(() => {
          btn.textContent = orig;
          btn.classList.remove('loading');
          btn.classList.add('done');
          btn.disabled = false;
        }, d.duration || 3000);
      }
      break;
    }
    case 'addExamResult':
      if (d.result) renderResult(d.result);
      break;
    case 'patientUpdate':
      if (d.medical) {
        currentMedical = d.medical;
        updateVitals(d.medical);
        updateBodyZones(d.medical.injuries || {});
        updateInjuriesList(d.medical.injuries || {});
        updateStateBadge(d.medical.state || 'conscious');
      }
      break;
    case 'finaliseDone':
      closeFinaliseModal();
      showToast(`📋 Dossier enregistré — Frais : ${d.cost ?? 0} $`, 'success');
      setTimeout(sendClose, 1200);
      break;
  }
  // hudUpdate / hudClear / hudDistant ignorés (EMS HUD supprimé)
});

// ── Ouvrir le panneau médical ─────────────────────
function openMedical(data) {
  try {
  currentMedical = data.medical || {};
  // S'assurer que injuries a toutes les zones
  // Normaliser injuries : Lua encode les tables vides en {} (objet), pas [] (tableau)
  const defaultZones = { head:[], torso:[], leftArm:[], rightArm:[], leftLeg:[], rightLeg:[] };
  const rawInj = currentMedical.injuries || {};
  currentMedical.injuries = {};
  for (const zone of Object.keys(defaultZones)) {
    const v = rawInj[zone];
    if (!v) {
      currentMedical.injuries[zone] = [];
    } else if (Array.isArray(v)) {
      currentMedical.injuries[zone] = v;
    } else {
      // Table Lua non-vide encodée en objet {0:{...}, 1:{...}} → convertir en tableau
      currentMedical.injuries[zone] = Object.values(v);
    }
  }
  currentPatient = data.patientName || data.playerName || 'Inconnu';
  isEmsMode      = !!data.isEms;
  sessionStart   = Date.now();

  document.getElementById('med-patient-name').textContent = currentPatient;

  updateStateBadge(currentMedical.state || 'conscious');
  updateVitals(currentMedical);
  updateBodyZones(currentMedical.injuries);
  updateInjuriesList(currentMedical.injuries);

  // Restaurer notes ou vider
  document.getElementById('med-notes').value = data.prevNotes || '';

  // Restaurer résultats précédents ou vider
  document.getElementById('results-list').innerHTML =
    '<div class="empty-results">Aucun examen.<br><small>Cliquez sur un examen pour démarrer.</small></div>';
  document.querySelectorAll('.exam-btn').forEach(b => { b.classList.remove('done'); b.disabled = false; });

  const prev = data.prevResults;
  if (prev && (Array.isArray(prev) ? prev.length > 0 : Object.keys(prev).length > 0)) {
    const arr = Array.isArray(prev) ? prev : Object.values(prev);
    arr.forEach(r => {
      renderResult(r);
      const btn = document.querySelector(`.exam-btn[data-exam="${r.type}"]`);
      if (btn) btn.classList.add('done');
    });
    updateDiagnosisSummary();
  }

  // Masquer les onglets exam si pas EMS (pour auto-fiche)
  const _tabs    = document.getElementById('center-tabs');
  const _tabExam = document.getElementById('tab-examens');
  const _tabProto= document.getElementById('tab-protocoles');
  if (!isEmsMode) {
    if (_tabs)     _tabs.style.display     = 'none';
    if (_tabExam)  _tabExam.style.display  = 'none';
    if (_tabProto) _tabProto.style.display = 'none';
  } else {
    if (_tabs)     _tabs.style.display     = '';
    if (_tabExam)  _tabExam.style.display  = '';
  }

  // Timer session
  clearInterval(timerInterval);
  timerInterval = setInterval(tickTimer, 1000);

  // Reset tabs et protocoles
  switchTab('examens');
  cancelProtocol();
  buildProtocolList();

  // Masquer ECG strip
  stopEcgStrip();
  document.getElementById('ecg-strip')?.classList.add('hidden');

  // Fermer la modal si ouverte
  closeFinaliseModal();

  document.getElementById('medical-wrap').classList.remove('hidden');
  } catch(e) {
    // En cas d'erreur JS, on s'assure de ne pas bloquer le joueur
    console.error('[nova_medical] openMedical error:', e);
    fetch('https://nova_medical/closeUI', { method:'POST', headers:{'Content-Type':'application/json'}, body:'{}' }).catch(()=>{});
  }
}

// ── Timer session ─────────────────────────────────
function tickTimer() {
  if (!sessionStart) return;
  const elapsed = Math.floor((Date.now() - sessionStart) / 1000);
  const m = String(Math.floor(elapsed / 60)).padStart(2, '0');
  const s = String(elapsed % 60).padStart(2, '0');
  document.getElementById('med-timer').textContent = `${m}:${s}`;
}

// ── State badge ───────────────────────────────────
function updateStateBadge(state) {
  const badge = document.getElementById('med-state-badge');
  const label = document.getElementById('med-state-label');
  const map   = {
    conscious: { cls: 'stable',   icon: 'fa-check-circle', text: 'Stable'   },
    injured:   { cls: 'injured',  icon: 'fa-exclamation-circle', text: 'Blessé'   },
    laststand: { cls: 'critical', icon: 'fa-heartbeat',    text: 'Critique' },
    dead:      { cls: 'dead',     icon: 'fa-skull',        text: 'Décédé'   },
  };
  const info = map[state] || map.conscious;
  badge.className = `state-badge ${info.cls}`;
  badge.querySelector('i').className = `fas ${info.icon}`;
  label.textContent = info.text;
}

// ── Vitaux ────────────────────────────────────────
function updateVitals(med) {
  // Si pas d'examens encore, on affiche —
  // Les vrais chiffres sont générés côté Lua (generateExamResult)
  // Ici on met juste à jour depuis les résultats d'examen
  // (les vitaux seront mis à jour via addExamResult)
}

function setVital(id, val, unit) {
  const chip = document.getElementById(id);
  if (!chip) return;
  // Support ancien (.vc-val) et nouveau (span direct) layout
  const valEl = chip.querySelector('.vc-val') || chip.querySelector('span');
  if (valEl) valEl.textContent = val ?? '—';
}

// ── Coloration des zones body ─────────────────────
const ZONE_SVG_IDS = {
  head:     'zone-head',
  torso:    'zone-torso',
  rightArm: 'zone-rightArm',
  leftArm:  'zone-leftArm',
  rightLeg: 'zone-rightLeg',
  leftLeg:  'zone-leftLeg',
};

const ZONE_LABELS = {
  head:     'Tête',
  torso:    'Torse',
  rightArm: 'Bras Droit',
  leftArm:  'Bras Gauche',
  rightLeg: 'Jambe Droite',
  leftLeg:  'Jambe Gauche',
};

function zoneClass(injuries) {
  if (!injuries || injuries.length === 0) return '';
  const maxSev = Math.max(...injuries.map(i => i.severity || 1));
  if (maxSev >= 5) return 'zone-critical';
  if (maxSev >= 4) return 'zone-severe';
  if (maxSev >= 3) return 'zone-moderate';
  if (maxSev >= 2) return 'zone-minor';
  return 'zone-healthy';
}

function updateBodyZones(injuries) {
  for (const [zone, svgId] of Object.entries(ZONE_SVG_IDS)) {
    const el = document.getElementById(svgId);
    if (!el) continue;
    el.setAttribute('class', 'body-zone');  // SVG : className est read-only
    const zInj = injuries[zone] || [];
    const cls  = zoneClass(zInj);
    if (cls) el.classList.add(cls);
  }
}

// ── Tooltip sur zones ─────────────────────────────
const tooltip = document.getElementById('zone-tooltip');

for (const [zone, svgId] of Object.entries(ZONE_SVG_IDS)) {
  const el = document.getElementById(svgId);
  if (!el) continue;

  el.addEventListener('mouseenter', (e) => {
    const zInj  = (currentMedical?.injuries || {})[zone] || [];
    const label = ZONE_LABELS[zone] || zone;
    if (zInj.length === 0) {
      tooltip.textContent = `${label} — Sain`;
    } else {
      const lines = zInj.map(i => `${i.type} (Sév. ${i.severity})`).join(', ');
      tooltip.textContent = `${label} — ${lines}`;
    }
    tooltip.classList.remove('hidden');
    positionTooltip(e);
  });

  el.addEventListener('mousemove', positionTooltip);
  el.addEventListener('mouseleave', () => tooltip.classList.add('hidden'));
}

function positionTooltip(e) {
  const container = document.getElementById('body-container');
  const rect      = container.getBoundingClientRect();
  const x         = e.clientX - rect.left;
  const y         = e.clientY - rect.top;
  tooltip.style.left = `${x}px`;
  tooltip.style.top  = `${y}px`;
}

// ── Liste des blessures ───────────────────────────
const ZONE_FR = {
  head: 'Tête', torso: 'Torse',
  rightArm: 'Bras D.', leftArm: 'Bras G.',
  rightLeg: 'Jambe D.', leftLeg: 'Jambe G.',
};

function updateInjuriesList(injuries) {
  const list = document.getElementById('injuries-list');
  const countEl = document.getElementById('injuries-count');
  let total = 0;
  list.innerHTML = '';

  for (const [zone, zInj] of Object.entries(injuries)) {
    for (const inj of zInj) {
      total++;
      const card = document.createElement('div');
      card.className = `inj-card sev-${Math.min(5, inj.severity || 1)}`;

      const dots = Array.from({length: 5}, (_, i) => {
        const filled = i < (inj.severity || 1);
        const red    = (inj.severity || 1) >= 4;
        return `<div class="inj-sev-dot ${filled ? 'filled' + (red ? ' red' : '') : ''}"></div>`;
      }).join('');

      card.innerHTML = `
        <div class="inj-zone">${ZONE_FR[zone] || zone}</div>
        <div class="inj-type">${formatInjuryType(inj.type)}</div>
        <div class="inj-sev-bar">${dots}</div>
      `;
      list.appendChild(card);
    }
  }

  countEl.textContent = total;
}

function formatInjuryType(type) {
  const map = {
    gunshot:   '🔴 Blessure par balle',
    stab:      '🔪 Lacération',
    blunt:     '🟡 Contusion',
    burn:      '🔥 Brûlure',
    explosion: '💥 Blast/Explosion',
    fracture:  '🦴 Fracture',
    internal:  '🩸 Hémorragie interne',
    crush:     '⚙️ Écrasement',
    shrapnel:  '⚡ Éclat',
    road:      '🚗 Abrasion voie publique',
    fall:      '⬇️ Trauma chute',
  };
  return map[type] || type;
}

// ── Exam buttons ──────────────────────────────────
document.querySelectorAll('.exam-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    if (!isEmsMode) return;
    const examId = btn.dataset.exam;
    fetch('https://nova_medical/startExam', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ examId }),
    });
    btn.classList.add('done');
  });
});

// ── Rendu des résultats ───────────────────────────
function renderResult(r) {
  const list = document.getElementById('results-list');

  // Vider le placeholder
  const empty = list.querySelector('.empty-results');
  if (empty) empty.remove();

  const card = document.createElement('div');
  card.className = 'result-card';

  const title = getExamTitle(r.type);
  const ts    = r.ts ? new Date(r.ts * 1000).toLocaleTimeString('fr-FR', { hour:'2-digit', minute:'2-digit', second:'2-digit' }) : '';

  let html = `<div class="rc-title"><i class="${getExamIcon(r.type)}"></i> ${title} <span style="margin-left:auto;font-size:9px;opacity:0.5">${ts}</span></div>`;

  switch (r.type) {
    case 'initial': {
      html += row('État', r.stateLabel || r.state);
      html += row('Sévérité', r.severity);
      html += row('Blessures', r.injuries);
      html += row('Pouls', r.pulse);
      html += row('Respiration', r.breathing);
      html += evalBadge(stateEval(r.state));
      break;
    }
    case 'bp': {
      html += row('Systolique', `${r.systolic} mmHg`);
      html += row('Diastolique', `${r.diastolic} mmHg`);
      html += row('Pouls', `${r.pulse} bpm`);
      html += evalBadge(bpEval(r.evaluation));
      // Mettre à jour vitaux
      document.getElementById('v-bp').textContent = `${r.systolic}/${r.diastolic}`;
      document.getElementById('v-bpm').textContent = r.pulse;
      chipState('vc-bp',  r.systolic >= 140 || r.systolic < 90 ? (r.systolic >= 140 ? 'warning' : 'danger') : '');
      chipState('vc-bpm', r.pulse > 100 ? 'warning' : r.pulse < 50 ? 'danger' : '');
      break;
    }
    case 'spo2': {
      html += row('SpO₂', `${r.spo2} %`);
      html += row('Éval.', r.evaluation);
      if (r.detail) html += row('Détail', r.detail);
      html += evalBadge(spo2Eval(r.spo2));
      document.getElementById('v-spo2').textContent = r.spo2;
      chipState('vc-spo2', r.spo2 < 88 ? 'danger' : r.spo2 < 95 ? 'warning' : '');
      break;
    }
    case 'neuro': {
      html += row('GCS Total', r.gcs);
      html += row('GCS Y/V/M', `${r.gcsO}/${r.gcsV}/${r.gcsM}`);
      html += row('Pupilles', r.pupils);
      html += evalBadge(gcsEval(r.gcs));
      break;
    }
    case 'ecg': {
      html += row('Rythme', r.rhythm);
      html += row('FC', `${r.bpm} bpm`);
      html += row('PR', `${r.pr} ms`);
      html += row('QRS', `${r.qrs} ms`);
      if (r.anomalies && r.anomalies.length) {
        html += `<div class="rc-row"><span class="rc-key">Anomalies</span><span class="rc-val" style="color:#fbbf24">${r.anomalies.join(', ')}</span></div>`;
      }
      html += evalBadge(ecgEval(r.evaluation));
      // Démarrer l'ECG strip animé
      startEcgStrip(r.bpm || 70, r.rhythm || 'normal');
      document.getElementById('v-bpm').textContent = r.bpm;
      chipState('vc-bpm', r.bpm > 120 ? 'warning' : r.bpm < 40 ? 'danger' : '');
      break;
    }
    case 'auscultation': {
      html += row('Cœur', `${r.heartSound} — ${r.bpm} bpm`);
      html += row('Murmure vés.', r.breathing);
      html += row('Râles', r.rales);
      html += row('Souffle', r.murmur);
      html += evalBadge(r.rales === 'présents' ? {cls:'warn', text:'Râles présents'} : {cls:'ok', text:'Normal'});
      break;
    }
    case 'glucose': {
      html += row('Glycémie', `${r.value} ${r.unit}`);
      html += evalBadge(glucoseEval(r.evaluation));
      break;
    }
    case 'temp': {
      html += row('Température', `${r.value} ${r.unit}`);
      html += evalBadge(tempEval(r.evaluation));
      document.getElementById('v-temp').textContent = r.value;
      chipState('vc-temp', r.evaluation === 'fièvre' ? 'warning' : r.evaluation === 'hypothermie' ? 'danger' : '');
      break;
    }
  }

  card.innerHTML = html;
  list.appendChild(card);
  list.scrollTop = list.scrollHeight;

  // Résumé diagnostic
  updateDiagnosisSummary();
}

// ── Helpers rendu résultats ───────────────────────
function row(k, v) {
  return `<div class="rc-row"><span class="rc-key">${k}</span><span class="rc-val">${v ?? '—'}</span></div>`;
}

function evalBadge({cls, text}) {
  return `<div><span class="rc-eval ${cls}">${text}</span></div>`;
}

function chipState(id, state) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.remove('danger', 'warning');
  if (state) el.classList.add(state);
}

function stateEval(state) {
  const m = { conscious: {cls:'ok', text:'Conscient'}, injured: {cls:'warn', text:'Blessé'},
    laststand: {cls:'danger', text:'Critique'}, dead: {cls:'danger', text:'Décédé'} };
  return m[state] || {cls:'info', text:state};
}

function bpEval(ev) {
  if (ev === 'hypertension') return {cls:'warn', text:'Hypertension'};
  if (ev === 'hypotension')  return {cls:'danger', text:'Hypotension'};
  return {cls:'ok', text:'Normale'};
}

function spo2Eval(v) {
  if (v >= 95) return {cls:'ok', text:'Normal'};
  if (v >= 88) return {cls:'warn', text:'Hypoxie légère'};
  return {cls:'danger', text:'Hypoxie sévère'};
}

function gcsEval(gcs) {
  if (gcs >= 13) return {cls:'ok', text:'GCS Normal'};
  if (gcs >= 9)  return {cls:'warn', text:'GCS Altéré'};
  return {cls:'danger', text:'GCS Critique'};
}

function ecgEval(ev) {
  if (ev === 'normal') return {cls:'ok', text:'Sinusal normal'};
  if (ev === 'tachycardie') return {cls:'warn', text:'Tachycardie'};
  if (ev === 'bradycardie') return {cls:'warn', text:'Bradycardie'};
  if (ev === 'fibrillation') return {cls:'danger', text:'Fibrillation ventriculaire'};
  if (ev === 'arrêt cardiaque') return {cls:'danger', text:'Arrêt cardiaque'};
  return {cls:'info', text:ev || '—'};
}

function glucoseEval(ev) {
  if (ev === 'hypoglycémie')  return {cls:'danger', text:'Hypoglycémie'};
  if (ev === 'hyperglycémie') return {cls:'warn',   text:'Hyperglycémie'};
  return {cls:'ok', text:'Normal'};
}

function tempEval(ev) {
  if (ev === 'hypothermie') return {cls:'danger', text:'Hypothermie'};
  if (ev === 'fièvre')      return {cls:'warn',   text:'Fièvre'};
  return {cls:'ok', text:'Normale'};
}

function getExamTitle(type) {
  const m = {
    initial:      'Évaluation initiale',
    bp:           'Tension artérielle',
    spo2:         'Saturation O₂',
    neuro:        'Examen neurologique',
    ecg:          'Électrocardiogramme',
    auscultation: 'Auscultation',
    glucose:      'Glycémie',
    temp:         'Température',
  };
  return m[type] || type;
}

function getExamIcon(type) {
  const m = {
    initial:      'fas fa-search',
    bp:           'fas fa-tachometer-alt',
    spo2:         'fas fa-lungs',
    neuro:        'fas fa-brain',
    ecg:          'fas fa-heartbeat',
    auscultation: 'fas fa-stethoscope',
    glucose:      'fas fa-tint',
    temp:         'fas fa-thermometer-half',
  };
  return m[type] || 'fas fa-vial';
}

// ── Résumé diagnostic ─────────────────────────────
function updateDiagnosisSummary() {
  // Résumé affiché uniquement dans la modal de finalisation (pas d'élément séparé)
}

function buildDiagSummary() {
  if (!currentMedical) return '';
  const injuries = currentMedical.injuries || {};
  let totalInj = 0, maxSev = 0, zones = [];
  for (const [zone, zInj] of Object.entries(injuries)) {
    if (zInj.length > 0) {
      totalInj += zInj.length;
      zones.push(ZONE_FR[zone] || zone);
      for (const inj of zInj) if ((inj.severity || 1) > maxSev) maxSev = inj.severity || 1;
    }
  }
  if (totalInj === 0) return 'Aucune blessure détectée.';
  const sevLabel = maxSev >= 4 ? '⚠️ Grave' : maxSev >= 3 ? '🟠 Modéré' : '🟡 Léger';
  let s = `${totalInj} blessure(s) — Sévérité ${sevLabel} — Zones : ${zones.join(', ')}`;
  if (currentMedical.bleeding) s += ' 🩸';
  return s;
}

// ── Finaliser fiche → ouvre la modal ─────────────
document.getElementById('btn-finalize')?.addEventListener('click', () => {
  if (isEmsMode) {
    openFinaliseModal();
  } else {
    sendClose();
  }
});

// ── Fermer ────────────────────────────────────────
document.getElementById('med-close')?.addEventListener('click', sendClose);

function sendClose() {
  // Sauvegarder les notes avant de fermer
  const notes = document.getElementById('med-notes')?.value?.trim() || '';
  fetch('https://nova_medical/saveNotes', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ notes }),
  }).catch(() => {});
  fetch('https://nova_medical/closeUI', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  closeAll();
}

function closeAll() {
  clearInterval(timerInterval);
  stopEcgStrip();
  closeFinaliseModal();
  document.getElementById('medical-wrap').classList.add('hidden');
  document.getElementById('death-screen').classList.add('hidden');
  document.getElementById('laststand-hud').classList.add('hidden');
}

// ── DEATH SCREEN ──────────────────────────────────
function showDeath(delaySeconds) {
  // Masquer le last stand HUD s'il était affiché
  document.getElementById('laststand-hud').classList.add('hidden');
  clearInterval(lsInterval);

  respawnDelay   = delaySeconds || 0;
  respawnUnlock  = Date.now() + respawnDelay * 1000;

  const btn = document.getElementById('btn-respawn');
  if (btn) {
    btn.disabled = respawnDelay > 0;
  }

  document.getElementById('death-screen').classList.remove('hidden');

  // Barre de saignement (décorative, part de 100% → 0 sur respawnDelay)
  const bar = document.getElementById('death-bleed-bar');
  if (bar) bar.style.width = '100%';

  clearInterval(respawnInterval);
  respawnInterval = setInterval(() => {
    const remaining = Math.max(0, Math.ceil((respawnUnlock - Date.now()) / 1000));
    const label     = document.getElementById('death-timer');
    if (label) {
      const m = String(Math.floor(remaining / 60)).padStart(2, '0');
      const s = String(remaining % 60).padStart(2, '0');
      label.textContent = `${m}:${s}`;
    }
    // Barre
    if (bar && respawnDelay > 0) {
      const pct = (remaining / respawnDelay) * 100;
      bar.style.width = `${pct}%`;
    }
    // Débloquer le bouton
    if (remaining <= 0) {
      clearInterval(respawnInterval);
      if (btn) btn.disabled = false;
      if (bar) bar.style.width = '0%';
    }
  }, 1000);
}

document.getElementById('btn-respawn')?.addEventListener('click', () => {
  if (document.getElementById('btn-respawn').disabled) return;
  fetch('https://nova_medical/requestRespawn', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
});

document.getElementById('btn-distress')?.addEventListener('click', () => {
  fetch('https://nova_medical/sendDistress', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  // Feedback visuel
  const btn = document.getElementById('btn-distress');
  btn.textContent = '✅ Signal envoyé !';
  btn.disabled    = true;
  setTimeout(() => {
    btn.innerHTML = '<kbd>G</kbd> Signal de détresse';
    btn.disabled  = false;
  }, 5000);
});

// ── LAST STAND HUD ────────────────────────────────
function showLastStand(durationSeconds) {
  lastStandEnd = Date.now() + durationSeconds * 1000;

  document.getElementById('laststand-hud').classList.remove('hidden');
  document.getElementById('death-screen').classList.add('hidden');

  const bar = document.getElementById('ls-bar');
  if (bar) bar.style.width = '100%';

  clearInterval(lsInterval);
  lsInterval = setInterval(() => {
    const remaining = Math.max(0, Math.ceil((lastStandEnd - Date.now()) / 1000));
    const m = String(Math.floor(remaining / 60)).padStart(2, '0');
    const s = String(remaining % 60).padStart(2, '0');
    document.getElementById('ls-timer').textContent = `${m}:${s}`;

    if (bar && durationSeconds > 0) {
      const pct = (remaining / durationSeconds) * 100;
      bar.style.width = `${pct}%`;
    }

    if (remaining <= 0) {
      clearInterval(lsInterval);
      document.getElementById('laststand-hud').classList.add('hidden');
    }
  }, 1000);
}

// ── Keyboard shortcuts ────────────────────────────
document.addEventListener('keydown', (e) => {
  // ESC ferme le panneau médical
  if (e.key === 'Escape') {
    if (!document.getElementById('medical-wrap').classList.contains('hidden')) {
      sendClose();
    }
    return;
  }

  // Touches death screen
  if (!document.getElementById('death-screen').classList.contains('hidden')) {
    if (e.key.toLowerCase() === 'g') {
      document.getElementById('btn-distress')?.click();
    }
    if (e.key.toLowerCase() === 'e') {
      const btn = document.getElementById('btn-respawn');
      if (btn && !btn.disabled) btn.click();
    }
  }
});

// ── Panel toujours opaque (pas de verre dépoli au survol) ──
// Le panel reste toujours solide — bordure et fond constants

// ══════════════════════════════════════════════════
//  TABS — Examens / Protocoles
// ══════════════════════════════════════════════════

document.querySelectorAll('.ctab').forEach(btn => {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab));
});

function switchTab(tab) {
  document.querySelectorAll('.ctab').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
  const examTab  = document.getElementById('tab-examens');
  const protoTab = document.getElementById('tab-protocoles');
  if (examTab)  examTab.classList.toggle('hidden',  tab !== 'examens');
  if (protoTab) protoTab.classList.toggle('hidden', tab !== 'protocoles');
}

// ══════════════════════════════════════════════════
//  PROTOCOLES
// ══════════════════════════════════════════════════

const PROTOCOLS = [
  {
    id: 'abcde', label: 'Bilan ABCDE', icon: '📋',
    steps: [
      { id:'A', label:'Airways — Voies aériennes', icon:'🫁', examId:'auscultation', hint:'Vérifier la liberté des voies aériennes' },
      { id:'B', label:'Breathing — Respiration',   icon:'💨', examId:'spo2',         hint:'Évaluer la ventilation et la SpO₂' },
      { id:'C', label:'Circulation',               icon:'💓', examId:'bp',           hint:'Bilan circulatoire, pouls et PA' },
      { id:'D', label:'Disability — Neuro',        icon:'🧠', examId:'neuro',        hint:'Score GCS et réactivité pupillaire' },
      { id:'E', label:'Exposure — Exposition',     icon:'🔍', examId:'initial',      hint:'Bilan lésionnel complet' },
    ]
  },
  {
    id: 'poly_trauma', label: 'Polytraumatisme', icon: '🚑',
    steps: [
      { id:'1', label:'Contrôle hémorragies',     icon:'🩸', examId:'initial',  hint:'Arrêter les saignements actifs' },
      { id:'2', label:'Liberté voies aériennes',  icon:'🫁', examId:'spo2',     hint:'Intubation si nécessaire' },
      { id:'3', label:'Bilan hémodynamique',      icon:'💓', examId:'bp',       hint:'Tension artérielle et FC' },
      { id:'4', label:'ECG de contrôle',          icon:'📈', examId:'ecg',      hint:'Rechercher trouble du rythme' },
      { id:'5', label:'Bilan neurologique',       icon:'🧠', examId:'neuro',    hint:'GCS et score de Glasgow' },
      { id:'6', label:'Glycémie + température',   icon:'🌡️', examId:'glucose',  hint:'Paramètres biologiques rapides' },
    ]
  },
  {
    id: 'cardiac', label: 'Arrêt cardiaque', icon: '❤️',
    steps: [
      { id:'1', label:'Confirmation arrêt',        icon:'💀', examId:'initial', hint:'Absence de pouls et de conscience' },
      { id:'2', label:'ECG — Rythme choquable ?',  icon:'📈', examId:'ecg',    hint:'FV ou TV → défibrillation' },
      { id:'3', label:'Ventilation assistée',      icon:'🫁', examId:'spo2',   hint:'Vérifier la ventilation assistée' },
      { id:'4', label:'Bilan post-réanimation',    icon:'🧠', examId:'neuro',  hint:'GCS et déficit neurologique' },
    ]
  },
];

let activeProtocol = null;
let activeStepIdx  = 0;

function buildProtocolList() {
  const list = document.getElementById('proto-list');
  if (!list) return;
  list.innerHTML = '';
  PROTOCOLS.forEach(p => {
    const card = document.createElement('div');
    card.className = 'proto-card';
    card.innerHTML = `
      <div class="proto-card-icon">${p.icon}</div>
      <div class="proto-card-info">
        <div class="proto-card-title">${p.label}</div>
        <div class="proto-card-steps">${p.steps.length} étapes</div>
      </div>
      <button class="proto-start-btn">Démarrer →</button>
    `;
    card.querySelector('.proto-start-btn').addEventListener('click', () => startProtocol(p));
    list.appendChild(card);
  });
}

function startProtocol(protocol) {
  if (!isEmsMode) return;
  activeProtocol = protocol;
  activeStepIdx  = 0;
  document.getElementById('proto-list').classList.add('hidden');
  document.getElementById('proto-active').classList.remove('hidden');
  document.getElementById('proto-active-label').textContent = `${protocol.icon} ${protocol.label}`;
  renderProtocolSteps();
}

function renderProtocolSteps() {
  const container = document.getElementById('proto-steps');
  if (!container) return;
  container.innerHTML = '';

  activeProtocol.steps.forEach((step, i) => {
    const isDone    = i < activeStepIdx;
    const isCurrent = i === activeStepIdx;

    const el = document.createElement('div');
    el.className = `proto-step ${isDone ? 'done' : ''} ${isCurrent ? 'current' : ''}`;
    el.innerHTML = `
      <div class="proto-step-badge ${isDone ? 'done' : isCurrent ? 'active' : ''}">${isDone ? '✓' : step.id}</div>
      <div class="proto-step-body">
        <div class="proto-step-label">${step.icon} ${step.label}</div>
        <div class="proto-step-hint">${step.hint}</div>
      </div>
      ${isCurrent ? `<button class="proto-step-btn" data-exam="${step.examId}">Lancer</button>` : ''}
    `;

    if (isCurrent) {
      el.querySelector('.proto-step-btn').addEventListener('click', () => launchProtocolStep(step));
    }
    container.appendChild(el);
  });

  const pct = (activeStepIdx / activeProtocol.steps.length) * 100;
  const bar = document.getElementById('proto-progress-bar');
  if (bar) bar.style.width = `${pct}%`;
}

function launchProtocolStep(step) {
  // Utilise protocolStep (NUI callback Lua dédié) pour garder la cohérence
  fetch('https://nova_medical/protocolStep', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ examId: step.examId }),
  });
  // Feedback immédiat sur le bouton
  const btn = document.querySelector('.proto-step-btn');
  if (btn) { btn.textContent = '⏳'; btn.disabled = true; }
  // Marquer aussi le bouton d'exam
  const examBtn = document.querySelector(`.exam-btn[data-exam="${step.examId}"]`);
  if (examBtn) examBtn.classList.add('done');
}

// Avancer le protocole quand un résultat arrive
function checkProtocolAdvance(examType) {
  if (!activeProtocol || activeStepIdx >= activeProtocol.steps.length) return;
  const current = activeProtocol.steps[activeStepIdx];
  if (current.examId === examType) {
    activeStepIdx++;
    if (activeStepIdx >= activeProtocol.steps.length) {
      showProtocolComplete();
    } else {
      renderProtocolSteps();
    }
  }
}

function showProtocolComplete() {
  const container = document.getElementById('proto-steps');
  const bar = document.getElementById('proto-progress-bar');
  if (container) container.innerHTML = `<div class="proto-complete">✅ Protocole terminé avec succès !<br><small>Tous les examens ont été réalisés.</small></div>`;
  if (bar) bar.style.width = '100%';
  setTimeout(cancelProtocol, 3500);
}

function cancelProtocol() {
  activeProtocol = null;
  activeStepIdx  = 0;
  const list   = document.getElementById('proto-list');
  const active = document.getElementById('proto-active');
  const bar    = document.getElementById('proto-progress-bar');
  if (list)   list.classList.remove('hidden');
  if (active) active.classList.add('hidden');
  if (bar)    bar.style.width = '0%';
}

document.getElementById('btn-proto-cancel')?.addEventListener('click', cancelProtocol);

// Hook renderResult pour avancer les protocoles
const _origRenderResult = renderResult;
// On surcharge checkProtocolAdvance après le rendu
const _renderResultWithProtocol = renderResult;
// Patch : après chaque résultat, vérifier avancement protocole
window.addEventListener('message', (event) => {
  if (event.data?.action === 'addExamResult' && event.data.result) {
    checkProtocolAdvance(event.data.result.type);
  }
});

// ══════════════════════════════════════════════════
//  ECG STRIP ANIMÉ
// ══════════════════════════════════════════════════

let _ecgRaf    = null;
let _ecgPhase  = 0;
let _ecgPrevY  = 23;
let _ecgBpm    = 70;
let _ecgRhythm = 'normal';

function startEcgStrip(bpm, rhythm) {
  stopEcgStrip();
  _ecgBpm    = bpm || 70;
  _ecgRhythm = rhythm || 'normal';
  _ecgPhase  = 0;

  const strip = document.getElementById('ecg-strip');
  const label = document.getElementById('ecg-rhythm-label');
  if (strip) strip.classList.remove('hidden');
  if (label) label.textContent = rhythm || 'normal';

  const canvas = document.getElementById('ecg-canvas');
  if (!canvas) return;
  const ctx    = canvas.getContext('2d');
  const W      = canvas.width;
  const H      = canvas.height;
  const mid    = H / 2;

  // Couleur selon rythme
  const traceColor = (_ecgRhythm === 'fibrillation' || _ecgRhythm === 'arrêt cardiaque') ? '#ef4444'
                   : _ecgRhythm === 'tachycardie' ? '#fbbf24'
                   : '#22c55e';

  _ecgPrevY = mid;

  function waveY(ph) {
    if (_ecgBpm === 0 || _ecgRhythm === 'arrêt cardiaque') return mid;
    if (_ecgRhythm === 'fibrillation') return mid + (Math.random() - 0.5) * 18;
    const p = ph % 1;
    if (p < 0.12) return mid - 4 * Math.sin((p / 0.12) * Math.PI);       // P
    if (p < 0.18) return mid;                                              // PR
    if (p < 0.20) return mid + 3;                                          // Q
    if (p < 0.22) return mid - (_ecgRhythm === 'tachycardie' ? 20 : 26);  // R
    if (p < 0.24) return mid + 5;                                          // S
    if (p < 0.28) return mid;                                              // ST
    if (p < 0.45) return mid - 7 * Math.sin(((p - 0.28) / 0.17) * Math.PI); // T
    return mid;
  }

  const speed = Math.max(0.4, Math.min(3.5, _ecgBpm / 55));

  function draw() {
    // Scroll left
    const img = ctx.getImageData(1, 0, W - 1, H);
    ctx.clearRect(0, 0, W, H);
    ctx.putImageData(img, 0, 0);
    // Effacer curseur droit
    ctx.clearRect(W - 3, 0, 3, H);
    // Ligne curseur subtile
    ctx.fillStyle = 'rgba(34,197,94,0.10)';
    ctx.fillRect(W - 2, 0, 2, H);

    _ecgPhase += speed * 0.007;
    const newY = waveY(_ecgPhase);

    ctx.beginPath();
    ctx.strokeStyle = traceColor;
    ctx.lineWidth   = 1.5;
    ctx.shadowColor = traceColor;
    ctx.shadowBlur  = 3;
    ctx.moveTo(W - 2, _ecgPrevY);
    ctx.lineTo(W - 1, newY);
    ctx.stroke();
    ctx.shadowBlur = 0;

    _ecgPrevY = newY;
    _ecgRaf   = requestAnimationFrame(draw);
  }
  draw();
}

function stopEcgStrip() {
  if (_ecgRaf) { cancelAnimationFrame(_ecgRaf); _ecgRaf = null; }
}

// ══════════════════════════════════════════════════
//  FINALISER MODAL
// ══════════════════════════════════════════════════

function openFinaliseModal() {
  const examsCount = document.querySelectorAll('.result-card').length;
  const stateLabel = document.getElementById('med-state-label')?.textContent || 'Inconnu';
  const diag       = buildDiagSummary();

  const summary = document.getElementById('fm-summary');
  if (summary) {
    summary.innerHTML = `
      <div class="fm-row"><span>Patient</span><strong>${currentPatient}</strong></div>
      <div class="fm-row"><span>État</span><strong>${stateLabel}</strong></div>
      <div class="fm-row"><span>Examens réalisés</span><strong>${examsCount}</strong></div>
      <div class="fm-summary-text">${diag}</div>
    `;
  }

  // Estimation coût
  const sl = stateLabel.toLowerCase();
  let est = '300 – 1 000 $';
  if (sl.includes('décédé') || sl.includes('critique')) est = '3 000 – 8 000 $';
  else if (sl.includes('blessé'))                        est = '1 000 – 2 500 $';
  const cp = document.getElementById('fm-cost-preview');
  if (cp) cp.textContent = `💰 Estimation des frais : ${est}`;

  const diag2 = document.getElementById('fm-diagnosis');
  if (diag2) diag2.value = '';

  const btn = document.getElementById('btn-fm-confirm');
  if (btn) { btn.textContent = '💾 Enregistrer & Facturer'; btn.disabled = false; }

  document.getElementById('finalise-modal')?.classList.remove('hidden');
}

function closeFinaliseModal() {
  document.getElementById('finalise-modal')?.classList.add('hidden');
}

document.getElementById('btn-fm-cancel')?.addEventListener('click', closeFinaliseModal);

document.getElementById('btn-fm-confirm')?.addEventListener('click', () => {
  const diag  = document.getElementById('fm-diagnosis')?.value?.trim() || '';
  const notes = document.getElementById('med-notes')?.value?.trim() || '';

  // Sauvegarder les notes
  fetch('https://nova_medical/saveNotes', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ notes }),
  }).catch(() => {});

  // Envoyer finaliser
  fetch('https://nova_medical/finaliser', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ diagnosis: diag }),
  });

  const btn = document.getElementById('btn-fm-confirm');
  if (btn) { btn.innerHTML = '⏳ Enregistrement...'; btn.disabled = true; }
});

// EMS HUD supprimé — utiliser le panel principal

// ══════════════════════════════════════════════════
//  TOAST NOTIFICATION
// ══════════════════════════════════════════════════

function showToast(message, type = 'info') {
  const container = document.getElementById('toast-container') || document.body;
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transition = 'opacity .3s';
    setTimeout(() => toast.remove(), 350);
  }, 3500);
}
