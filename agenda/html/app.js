// ─────────────────────────────────────────────────────────────────────────────
// Agenda UI — logique principale
// ─────────────────────────────────────────────────────────────────────────────
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'agenda';
const isEmbedded = window.parent !== window;

if (isEmbedded) document.documentElement.classList.add('embedded');

function agendaSend(action, data) {
  return fetch(`https://${RES}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).then(r => r.json().catch(() => ({})));
}

// ── SVG helpers ───────────────────────────────────────────────────────────────
const ICON = {
  back:    `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M15 18l-6-6 6-6"/></svg>`,
  chevron: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M9 18l6-6-6-6"/></svg>`,
  clock:   `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>`,
};

// ── État global ───────────────────────────────────────────────────────────────
const app     = document.getElementById('app');
const content = document.getElementById('content');
const tabsEl  = document.getElementById('tabs');

let allBusinesses = {};
let staffCtx      = null;

// ── Gestion ouverture / fermeture ─────────────────────────────────────────────
window.addEventListener('message', (e) => {
  const msg = e.data || {};
  if (msg.action === 'open') {
    allBusinesses = msg.businesses || {};
    staffCtx      = null;
    renderBusinesses(allBusinesses);
    showTabs('bookings');
    show(true);
    agendaSend('getStaffContext').then(res => {
      if (res.ok && res.businessId) {
        staffCtx = { businessId: res.businessId, label: res.label };
        showTabs('bookings');
      }
    });
  }
});

document.getElementById('close').onclick = () => {
  if (isEmbedded) {
    window.parent.postMessage({ type: 'agenda:close' }, '*');
  } else {
    agendaSend('close');
    show(false);
  }
};

function show(v) {
  app.classList.toggle('hidden', !v);
  if (!v) { staffCtx = null; tabsEl.classList.add('hidden'); tabsEl.innerHTML = ''; }
}

// ── Onglets ───────────────────────────────────────────────────────────────────
function showTabs(active) {
  tabsEl.innerHTML = '';
  tabsEl.classList.remove('hidden');
  const defs = [['bookings', 'Réservations'], ['myrdv', 'Mes RDV']];
  if (staffCtx) defs.push(['staff', 'Staff']);
  defs.forEach(([id, label]) => {
    const btn = document.createElement('button');
    btn.className = 'tab' + (active === id ? ' active' : '');
    btn.textContent = label;
    btn.onclick = () => {
      if      (id === 'bookings') { renderBusinesses(allBusinesses); showTabs('bookings'); }
      else if (id === 'myrdv')    { loadMyAppointments();            showTabs('myrdv');    }
      else                        { loadStaff();                     showTabs('staff');    }
    };
    tabsEl.appendChild(btn);
  });
}

// ── Vue : liste des établissements ────────────────────────────────────────────
function renderBusinesses(businesses) {
  content.innerHTML = '';

  const lbl = mk('p', 'sec-label', 'Établissements disponibles');
  content.appendChild(lbl);

  Object.entries(businesses).forEach(([id, b]) => {
    const card = mk('div', 'biz-card');
    card.innerHTML = `
      <div class="biz-accent" style="background:${b.color || '#3C64B1'}"></div>
      <div class="biz-body">
        <div class="biz-name">${esc(b.label)}</div>
        <div class="biz-meta"><span class="biz-badge">${esc(b.type)}</span></div>
      </div>
      <div class="biz-arrow">${ICON.chevron}</div>`;
    card.onclick = () => renderServices(id, b);
    content.appendChild(card);
  });

  if (!Object.keys(businesses).length) {
    content.appendChild(mk('p', 'msg msg-neu', 'Aucun établissement configuré.'));
  }
}

// ── Vue : services d'un établissement ────────────────────────────────────────
function renderServices(businessId, b) {
  content.innerHTML = '';

  const back = backBtn(() => renderBusinesses(allBusinesses));
  content.appendChild(back);

  const subHd = mk('div', 'sub-hd');
  subHd.innerHTML = `
    <div class="sub-hd-title">${esc(b.label)}</div>
    <div class="sub-hd-meta">Choisissez un service</div>`;
  content.appendChild(subHd);

  (b.services || []).forEach(s => {
    const row = mk('button', 'svc-row');
    row.innerHTML = `
      <div class="svc-info">
        <div class="svc-name">${esc(s.name)}</div>
        <div class="svc-meta">${s.duration} min · ${s.price}&nbsp;$</div>
      </div>
      <div class="svc-arrow">${ICON.chevron}</div>`;
    row.onclick = async () => {
      row.style.opacity = '0.5';
      const res = await agendaSend('getSlots', { businessId, serviceId: s.id });
      row.style.opacity = '';
      renderSlots(businessId, b, s, res.slots || []);
    };
    content.appendChild(row);
  });
}

// ── Vue : créneaux ────────────────────────────────────────────────────────────
function renderSlots(businessId, b, svc, slots, notice) {
  content.innerHTML = '';

  content.appendChild(backBtn(() => renderServices(businessId, b)));

  const subHd = mk('div', 'sub-hd');
  subHd.innerHTML = `
    <div class="sub-hd-title">${esc(b.label)}</div>
    <div class="sub-hd-meta">${esc(svc.name)} · ${svc.duration} min · ${svc.price}&nbsp;$</div>`;
  content.appendChild(subHd);

  if (notice) {
    const n = mk('p', `msg ${notice.type === 'err' ? 'msg-err' : 'msg-ok'}`, notice.text);
    content.appendChild(n);
    if (notice.type === 'ok') setTimeout(() => n.remove(), 3500);
  }

  if (!slots.length) {
    content.appendChild(mk('p', 'msg msg-neu', 'Aucun créneau disponible pour ce service.'));
    return;
  }

  // Grouper par jour
  const byDay = {};
  slots.forEach(slot => {
    const dt  = parseDate(slot.start_time);
    const key = dt.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    if (!byDay[key]) byDay[key] = [];
    byDay[key].push({ slot, dt });
  });

  Object.entries(byDay).forEach(([dayStr, items]) => {
    content.appendChild(mk('p', 'slot-day', dayStr));
    const row = mk('div', 'slot-pills');
    items.forEach(({ slot, dt }) => {
      const timeStr = dt.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
      const pill = mk('button', 'slot-pill', timeStr);
      pill.onclick = async () => {
        pill.disabled = true;
        const res = await agendaSend('book', { slotId: slot.id });
        if (res.ok) {
          pill.classList.add('booked');
          pill.textContent = '✓ ' + timeStr;
          const n = mk('p', 'msg msg-ok', 'Rendez-vous confirmé !');
          subHd.insertAdjacentElement('afterend', n);
          setTimeout(() => n.remove(), 4000);
        } else if (res.error === 'creneau_pris') {
          pill.disabled = false;
          const fresh = await agendaSend('getSlots', { businessId, serviceId: svc.id });
          renderSlots(businessId, b, svc, fresh.slots || [], {
            text: 'Ce créneau vient d\'être pris. Liste actualisée.',
            type: 'err',
          });
        } else {
          pill.disabled = false;
        }
      };
      row.appendChild(pill);
    });
    content.appendChild(row);
  });
}

// ── Vue : mes rendez-vous ─────────────────────────────────────────────────────
async function loadMyAppointments() {
  content.innerHTML = '';
  content.appendChild(mk('p', 'msg msg-neu', 'Chargement…'));
  const res = await agendaSend('getMyAppointments');
  if (!res.ok) {
    content.innerHTML = '';
    content.appendChild(mk('p', 'msg msg-err', 'Impossible de charger vos rendez-vous.'));
    return;
  }
  renderMyAppointments(res.appointments || []);
}

function renderMyAppointments(appointments) {
  content.innerHTML = '';
  content.appendChild(mk('p', 'sec-label', 'Mes rendez-vous à venir'));

  if (!appointments.length) {
    content.appendChild(mk('p', 'msg msg-neu', 'Aucun rendez-vous à venir.'));
    return;
  }

  appointments.forEach(appt => {
    const dt      = parseDate(appt.start_time);
    const dayNum  = dt.getDate();
    const month   = dt.toLocaleDateString('fr-FR', { month: 'short' });
    const timeStr = dt.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

    const biz     = allBusinesses[appt.business_id] || {};
    const svc     = (biz.services || []).find(s => s.id === appt.service_id);
    const bizName = biz.label || appt.business_id;
    const svcName = svc ? svc.name : appt.service_id;

    const card = mk('div', 'appt-card');
    card.innerHTML = `
      <div class="appt-cal">
        <div class="appt-cal-month">${esc(month)}</div>
        <div class="appt-cal-day">${dayNum}</div>
      </div>
      <div class="appt-body">
        <div class="appt-biz">${esc(bizName)}</div>
        <div class="appt-svc">${esc(svcName)}</div>
        <div class="appt-time">${ICON.clock} à ${timeStr}</div>
      </div>
      <div class="appt-side">
        <button class="btn-cancel">Annuler</button>
      </div>`;

    const btnCancel = card.querySelector('.btn-cancel');
    let confirming  = false;
    let resetTimer  = null;

    btnCancel.onclick = async () => {
      if (!confirming) {
        confirming = true;
        btnCancel.textContent = 'Confirmer ?';
        btnCancel.classList.add('confirming');
        resetTimer = setTimeout(() => {
          confirming = false;
          btnCancel.textContent = 'Annuler';
          btnCancel.classList.remove('confirming');
        }, 3000);
        return;
      }
      clearTimeout(resetTimer);
      btnCancel.disabled = true;
      const res = await agendaSend('cancelAppointment', { apptId: appt.id });
      if (res.ok) {
        card.remove();
        content.appendChild(mk('p', 'msg msg-ok', 'Rendez-vous annulé.'));
      } else {
        confirming = false;
        btnCancel.disabled   = false;
        btnCancel.textContent = 'Annuler';
        btnCancel.classList.remove('confirming');
        card.insertAdjacentElement('afterend', mk('p', 'msg msg-err', 'Erreur, veuillez réessayer.'));
      }
    };

    content.appendChild(card);
  });
}

// ── Vue : staff ───────────────────────────────────────────────────────────────
async function loadStaff() {
  content.innerHTML = '';
  content.appendChild(mk('p', 'msg msg-neu', 'Chargement…'));
  const res = await agendaSend('getStaffAppointments');
  if (!res.ok) {
    content.innerHTML = '';
    content.appendChild(mk('p', 'msg msg-err', 'Impossible de charger les rendez-vous.'));
    return;
  }
  renderStaff(res.appointments || []);
}

function renderStaff(appointments) {
  content.innerHTML = '';

  const today = new Date().toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
  const subHd = mk('div', 'sub-hd');
  subHd.innerHTML = `
    <div class="sub-hd-title">${esc(staffCtx ? staffCtx.label : 'Mon établissement')}</div>
    <div class="sub-hd-meta">Rendez-vous du ${today}</div>`;
  content.appendChild(subHd);

  if (!appointments.length) {
    content.appendChild(mk('p', 'msg msg-neu', 'Aucun rendez-vous aujourd\'hui.'));
    return;
  }

  const BADGE = {
    pending:   ['badge-pending',   'En attente'],
    confirmed: ['badge-confirmed', 'Confirmé'],
    done:      ['badge-done',      'Honoré'],
    noshow:    ['badge-noshow',    'Absent'],
    cancelled: ['badge-cancelled', 'Annulé'],
  };

  appointments.forEach(appt => {
    const dt      = parseDate(appt.start_time);
    const timeStr = dt.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

    const biz     = staffCtx ? (allBusinesses[staffCtx.businessId] || {}) : {};
    const svc     = (biz.services || []).find(s => s.id === appt.service_id);
    const svcName = svc ? svc.name : appt.service_id;

    const [badgeCls, badgeLabel] = BADGE[appt.status] || BADGE.pending;
    const isDone = ['done', 'noshow', 'cancelled'].includes(appt.status);

    const card = mk('div', 'staff-card');
    card.innerHTML = `
      <div class="staff-time">${timeStr}</div>
      <div class="staff-info">
        <div class="staff-svc">${esc(svcName)}</div>
        <div class="staff-cit">${esc(appt.citizen)}</div>
        <span class="badge ${badgeCls}">${badgeLabel}</span>
      </div>
      <div class="staff-acts">
        <button class="btn-done"   title="Honoré"  ${isDone ? 'disabled' : ''}>✓</button>
        <button class="btn-noshow" title="Absent"   ${isDone ? 'disabled' : ''}>✗</button>
      </div>`;

    if (!isDone) {
      const btnDone   = card.querySelector('.btn-done');
      const btnNoshow = card.querySelector('.btn-noshow');
      const setStatus = async (status) => {
        btnDone.disabled = btnNoshow.disabled = true;
        const res = await agendaSend('setAppointmentStatus', { apptId: appt.id, status });
        if (res.ok) {
          const [cls, lbl] = BADGE[status];
          const badge = card.querySelector('.badge');
          badge.className = `badge ${cls}`;
          badge.textContent = lbl;
        } else {
          btnDone.disabled = btnNoshow.disabled = false;
        }
      };
      btnDone.onclick   = () => setStatus('done');
      btnNoshow.onclick = () => setStatus('noshow');
    }

    content.appendChild(card);
  });
}

// ── Utilitaires ───────────────────────────────────────────────────────────────
function mk(tag, cls, text) {
  const el = document.createElement(tag);
  if (cls)  el.className   = cls;
  if (text) el.textContent = text;
  return el;
}

function esc(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// Parsing robuste : ajoute 'Z' uniquement si la chaîne est sans offset
// pour éviter le décalage de timezone (bug #28 de l'audit)
function parseDate(str) {
  if (!str) return new Date(NaN);
  // Déjà avec offset ? Conserver tel quel
  if (/[Z+\-]\d{0,2}:?\d{0,2}$/.test(str)) return new Date(str.replace(' ', 'T'));
  // Sinon traiter comme UTC serveur
  return new Date(str.replace(' ', 'T') + 'Z');
}

function backBtn(fn) {
  const btn = mk('button', 'btn-back');
  btn.innerHTML = ICON.back + ' Retour';
  btn.onclick = fn;
  return btn;
}
