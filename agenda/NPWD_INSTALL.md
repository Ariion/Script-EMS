# Intégration NPWD — Agenda

## Ce que ça fait

L'agenda devient une vraie **app du téléphone NPWD**.  
Le bezel/habillage téléphone reste toujours visible. L'agenda s'affiche dans
la zone écran, comme n'importe quelle autre app NPWD.

Architecture :
```
NPWD (téléphone)
└── écran app "/agenda"
    └── React component (remoteEntry.js servi par la resource agenda)
        └── <iframe src="https://agenda/html/index.html">
               (toute la logique UI existante, callbacks NUI inchangés)
```

---

## Installation

### 1. Rebuilder si tu modifies le code React

```bash
cd resources/agenda/npwd_app
npm install   # une seule fois
npm run build # regénère dist/
```

Les fichiers `dist/` sont déjà inclus dans le dépôt ; **rebuilder uniquement
si tu modifies `src/App.tsx`**.

---

### 2. Enregistrer l'app dans NPWD

Ouvre `resources/npwd/npwd.config.js` et ajoute dans le tableau `apps` :

```js
// npwd.config.js
module.exports = {
  // ...configuration existante...

  apps: [
    // ...autres apps...
    {
      id: 'AGENDA',
      nameLocale: 'Agenda',
      // Icône : chemin relatif à npwd/html/ ou URL https://
      icon: 'https://agenda/html/icon.png',  // (optionnel)
      path: '/agenda',
      // Module Federation : "nom_module@URL_remoteEntry"
      app: 'agenda@https://agenda/npwd_app/dist/remoteEntry.js',
    },
  ],
};
```

> **Note :** certaines versions de NPWD utilisent `externalApps` au lieu de
> `apps`. Si `apps` n'existe pas, essaie :
> ```js
> externalApps: [{ id:'AGENDA', ... }]
> ```

---

### 3. Ordre dans server.cfg

```cfg
ensure oxmysql
ensure npwd          # AVANT agenda
ensure agenda
```

---

## Utilisation en jeu

| Action | Résultat |
|--------|---------|
| `/agenda` en chat | Affiche le téléphone NPWD |
| Tap sur l'icône Agenda | Ouvre l'app dans le téléphone |
| Bouton × dans l'agenda | Retour à l'écran d'accueil NPWD |

---

## Comment ça marche (flux complet)

1. NPWD charge `remoteEntry.js` depuis `https://agenda/npwd_app/dist/`  
2. Quand le joueur navigue vers `/agenda`, NPWD monte le composant React  
3. Le composant crée une `<iframe src="https://agenda/html/index.html">`  
4. `onLoad` → `fetch('https://agenda/getBusinesses')` → retourne `Config.Businesses`  
5. Le composant envoie `{ action:'open', businesses }` à l'iframe via `postMessage`  
6. L'iframe affiche la liste des entreprises  
7. Bouton × → `window.parent.postMessage({ type:'agenda:close' })`  
8. Le composant React reçoit le message → `history.push('/')` → retour accueil NPWD  

---

## Mode standalone (sans NPWD)

Si NPWD n'est pas lancé, `Config.Phone = 'auto'` détecte automatiquement
lb-phone / qb-phone / standalone. La commande `/agenda` ouvre alors l'UI
en plein écran comme avant (sans bezel téléphone).
