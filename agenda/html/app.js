// Cœur UI : appelle TOUJOURS la meme fonction, quel que soit le telephone.
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'agenda';

function agendaSend(action, data) {
  return fetch(`https://${RES}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {})
  }).then(r => r.json().catch(() => ({})));
}

const app     = document.getElementById('app');
const content = document.getElementById('content');
const tabsEl  = document.getElementById('tabs');

let allBusinesses = {};
let staffCtx      = null;

window.addEventListener('message', (e) => {
  const msg = e.data || {};
  if (msg.action === 'open') {
    allBusinesses = msg.businesses || {};
    staffCtx = null;
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

document.getElementById('close').onclick = () => { agendaSend('close'); show(false); };

function show(v) {
  app.classList.toggle('hidden', !v);
  if (!v) { staffCtx = null; tabsEl.classList.add('hidden'); tabsEl.innerHTML = ''; }
}

// ── Onglets ────────────────────────────────────────────────────────────────

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

// ── Vue Réservations ───────────────────────────────────────────────────────

function renderBusinesses(businesses) {
  content.innerHTML = '';
  Object.entries(businesses).forEach(([id, b]) => {
    const card = document.createElement('div');
    card.className = 'card';
    card.style.borderColor = b.color || '#0aa4c4';
    card.innerHTML = `<h3>${b.label}</h3><small>${b.type}</small>`;
    card.onclick = () => renderServices(id, b);
    content.appendChild(card);
  });
}

function renderServices(businessId, b) {
  content.innerHTML = `<button class="back">&larr;</button><h2>${b.label}</h2>`;
  content.querySelector('.back').onclick = () => renderBusinesses({ [businessId]: b });
  (b.services || []).forEach(s => {
    const row = document.createElement('button');
    row.className = 'service';
    row.textContent = `${s.name} — ${s.price}$ (${s.duration} min)`;
    row.onclick = async () => {
      row.disabled = true;
      const res = await agendaSend('getSlots', { businessId, serviceId: s.id });
      renderSlots(businessId, b, s, res.slots || []);
    };
    content.appendChild(row);
  });
}

function renderSlots(businessId, b, svc, slots, notice) {
  content.innerHTML = '';

  const back = document.createElement('button');
  back.className = 'back';
  back.innerHTML = '&larr;';
  back.onclick = () => renderServices(businessId, b);
  content.appendChild(back);

  const h2 = document.createElement('h2');
  h2.textContent = b.label;
  content.appendChild(h2);

  const sub = document.createElement('p');
  sub.className = 'svc-label';
  sub.textContent = `${svc.name} — ${svc.duration} min — ${svc.price} $`;
  content.appendChild(sub);

  if (notice) {
    const n = document.createElement('p');
    n.className = `msg ${notice.type}`;
    n.textContent = notice.text;
    content.appendChild(n);
    if (notice.type === 'ok') setTimeout(() => n.remove(), 3500);
  }

  if (!slots.length) {
    const empty = document.createElement('p');
    empty.className = 'msg';
    empty.textContent = 'Aucun créneau disponible pour ce service.';
    content.appendChild(empty);
    return;
  }

  slots.forEach(slot => {
    const dt      = new Date(slot.start_time.replace(' ', 'T'));
    const dateStr = dt.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    const timeStr = dt.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

    const row = document.createElement('div');
    row.className = 'slot';
    row.innerHTML = `<span class="slot-time"><b>${dateStr}</b> à ${timeStr}</span><button class="slot-book">Réserver</button>`;

    row.querySelector('.slot-book').onclick = async (e) => {
      const btn = e.currentTarget;
      btn.disabled = true;
      const res = await agendaSend('book', { slotId: slot.id });
      if (res.ok) {
        row.remove();
        const n = document.createElement('p');
        n.className = 'msg ok';
        n.textContent = 'Réservation confirmée !';
        content.appendChild(n);
        setTimeout(() => n.remove(), 3500);
      } else if (res.error === 'creneau_pris') {
        const fresh = await agendaSend('getSlots', { businessId, serviceId: svc.id });
        renderSlots(businessId, b, svc, fresh.slots || [], {
          text: 'Ce créneau vient d\'être pris. Liste mise à jour.',
          type: 'err'
        });
      } else {
        const n = document.createElement('p');
        n.className = 'msg err';
        n.textContent = 'Une erreur est survenue, veuillez réessayer.';
        row.insertAdjacentElement('beforebegin', n);
        btn.disabled = false;
      }
    };

    content.appendChild(row);
  });
}

// ── Mes RDV ────────────────────────────────────────────────────────────────

async function loadMyAppointments() {
  content.innerHTML = '<p class="msg">Chargement…</p>';
  const res = await agendaSend('getMyAppointments');
  if (!res.ok) {
    content.innerHTML = '<p class="msg err">Impossible de charger vos rendez-vous.</p>';
    return;
  }
  renderMyAppointments(res.appointments || []);
}

function renderMyAppointments(appointments) {
  content.innerHTML = '';

  const h2 = document.createElement('h2');
  h2.textContent = 'Mes rendez-vous';
  content.appendChild(h2);

  if (!appointments.length) {
    const empty = document.createElement('p');
    empty.className = 'msg';
    empty.textContent = 'Aucun rendez-vous à venir.';
    content.appendChild(empty);
    return;
  }

  appointments.forEach(appt => {
    const dt      = new Date(appt.start_time.replace(' ', 'T'));
    const dateStr = dt.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    const timeStr = dt.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

    const biz     = allBusinesses[appt.business_id] || {};
    const svc     = (biz.services || []).find(s => s.id === appt.service_id);
    const bizName = biz.label || appt.business_id;
    const svcName = svc ? svc.name : appt.service_id;

    const row = document.createElement('div');
    row.className = 'my-appt';
    row.innerHTML = `
      <div class="appt-info">
        <b>${bizName} — ${svcName}</b>
        <span>${dateStr} à ${timeStr}</span>
      </div>
      <button class="btn-cancel">Annuler</button>`;

    const btnCancel = row.querySelector('.btn-cancel');
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
        row.remove();
        const n = document.createElement('p');
        n.className = 'msg ok';
        n.textContent = 'Rendez-vous annulé. Le créneau est à nouveau disponible.';
        content.appendChild(n);
        setTimeout(() => n.remove(), 4000);
      } else {
        confirming = false;
        btnCancel.disabled = false;
        btnCancel.textContent = 'Annuler';
        btnCancel.classList.remove('confirming');
        const n = document.createElement('p');
        n.className = 'msg err';
        n.textContent = 'Erreur lors de l\'annulation, veuillez réessayer.';
        row.insertAdjacentElement('afterend', n);
        setTimeout(() => n.remove(), 3000);
      }
    };

    content.appendChild(row);
  });
}

// ── Vue Staff ──────────────────────────────────────────────────────────────

async function loadStaff() {
  content.innerHTML = '<p class="msg">Chargement…</p>';
  const res = await agendaSend('getStaffAppointments');
  if (!res.ok) {
    content.innerHTML = '<p class="msg err">Impossible de charger les rendez-vous.</p>';
    return;
  }
  renderStaff(res.appointments || []);
}

function renderStaff(appointments) {
  content.innerHTML = '';

  const h2 = document.createElement('h2');
  h2.textContent = staffCtx ? staffCtx.label : 'Mon établissement';
  content.appendChild(h2);

  const today = new Date().toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
  const sub = document.createElement('p');
  sub.className = 'svc-label';
  sub.textContent = `Rendez-vous du ${today}`;
  content.appendChild(sub);

  if (!appointments.length) {
    const empty = document.createElement('p');
    empty.className = 'msg';
    empty.textContent = 'Aucun rendez-vous aujourd\'hui.';
    content.appendChild(empty);
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
    const dt      = new Date(appt.start_time.replace(' ', 'T'));
    const timeStr = dt.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

    const biz     = staffCtx ? (allBusinesses[staffCtx.businessId] || {}) : {};
    const svc     = (biz.services || []).find(s => s.id === appt.service_id);
    const svcName = svc ? svc.name : appt.service_id;

    const [badgeCls, badgeLabel] = BADGE[appt.status] || BADGE.pending;
    const isDone = appt.status === 'done' || appt.status === 'noshow' || appt.status === 'cancelled';

    const row = document.createElement('div');
    row.className = 'appt';
    row.innerHTML = `
      <div class="appt-info">
        <b>${timeStr} — ${svcName}</b>
        <small>${appt.citizen}</small>
        <span class="badge ${badgeCls}">${badgeLabel}</span>
      </div>
      <div class="appt-actions">
        <button class="btn-done"   ${isDone ? 'disabled' : ''}>Honoré</button>
        <button class="btn-noshow" ${isDone ? 'disabled' : ''}>Absent</button>
      </div>`;

    if (!isDone) {
      const btnDone   = row.querySelector('.btn-done');
      const btnNoshow = row.querySelector('.btn-noshow');

      const setStatus = async (status) => {
        btnDone.disabled = true;
        btnNoshow.disabled = true;
        const res = await agendaSend('setAppointmentStatus', { apptId: appt.id, status });
        if (res.ok) {
          const [cls, lbl] = BADGE[status];
          const badge = row.querySelector('.badge');
          badge.className = `badge ${cls}`;
          badge.textContent = lbl;
        } else {
          btnDone.disabled = false;
          btnNoshow.disabled = false;
          const n = document.createElement('p');
          n.className = 'msg err';
          n.textContent = 'Erreur lors de la mise à jour.';
          row.insertAdjacentElement('afterend', n);
          setTimeout(() => n.remove(), 3000);
        }
      };

      btnDone.onclick   = () => setStatus('done');
      btnNoshow.onclick = () => setStatus('noshow');
    }

    content.appendChild(row);
  });
}
