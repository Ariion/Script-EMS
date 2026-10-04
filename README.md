# Script EMS — Novacity FiveM

Scripts médicaux pour serveur FiveM ESX Legacy.

---

## 📁 Contenu du repo

```
Script-EMS/
├── nova_medical/       ← Système médical principal (EMS)
├── agenda/             ← Prise de rendez-vous in-game
└── demo/               ← Démo standalone (navigateur)
```

---

## 🏥 nova_medical

Système médical complet pour les soignants (ambulanciers OMC).

### Fonctionnalités
- **Panneau de diagnostic** côté gauche — fond semi-transparent, vue sur le patient
- **8 examens** : Évaluation, Tension, SpO₂, Neuro, ECG animé, Auscultation, Glycémie, Température
- **3 protocoles guidés** : Bilan ABCDE, Polytraumatisme, Arrêt cardiaque
- **Blessures par zone** : tête, torse, bras gauche/droit, jambe gauche/droite
- **Debuffs gameplay** : boiterie (clipset injured), interdiction de conduire, hémorragie
- **Last Stand** : compte à rebours avant mort définitive (8 min)
- **Écran de mort** : signal de détresse, réapparition hôpital avec délai
- Facturation automatique selon l'état du patient

### Stack
- ESX Legacy + ox_lib + ox_target + oxmysql
- NUI : HTML/CSS/JS vanilla (aucune dépendance)

### Installation
1. Copier `nova_medical/` dans `resources/[standalone]/`
2. Importer `nova_medical.sql` dans HeidiSQL
3. Ajouter dans `server.cfg` :
   ```
   ensure nova_medical
   ```

### Structure
```
nova_medical/
├── fxmanifest.lua
├── nova_medical.sql
├── shared/
│   └── config.lua          ← Debuffs, seuils, timers
├── client/
│   ├── main.lua            ← NUI, debuffs, animations
│   ├── examination.lua     ← Examens médicaux
│   ├── treatment.lua       ← Soins et traitements
│   ├── hud.lua             ← HUD état joueur
│   ├── bag.lua             ← Sac médical
│   └── stretcher.lua       ← Brancard
├── server/
│   └── main.lua            ← Callbacks, facturation
└── ui/
    ├── index.html
    ├── style.css           ← v7
    └── script.js           ← v15
```

---

## 📅 agenda

Système de prise de rendez-vous in-game pour les entreprises (hôpital, garage...).

### Fonctionnalités
- Réservation de créneaux horaires par les civils
- Vue staff pour les employés
- Rappel automatique X minutes avant le RDV
- Configurable par entreprise (services, horaires, tarifs)
- Compatible ESX Legacy / QBCore / standalone

### Installation
1. Copier `agenda/` dans `resources/[standalone]/`
2. Importer `agenda/sql/agenda.sql` dans HeidiSQL
3. Ajouter dans `server.cfg` :
   ```
   ensure agenda
   ```
4. Configurer les entreprises dans `agenda/config.lua`

### Configuration rapide
```lua
Config.Businesses = {
  ['omc'] = {
    label = 'Ocean Medical Center', type = 'hospital',
    color = '#0aa4c4', job = 'ambulance',
    services = {
      { id = 'consult', name = 'Consultation', duration = 15, price = 150 },
    }
  },
}
Config.OpenHour        = 8
Config.CloseHour       = 22
Config.ReminderMinutes = 10
```

---

## 🌐 Démo interactive

Le dossier `demo/` contient une version standalone de l'interface nova_medical (aucun serveur FiveM requis).

**[→ Voir la démo en ligne](https://ariion.github.io/Script-EMS/demo/)** *(après activation GitHub Pages)*

Scénarios disponibles : fusillade, accident, couteau, chute, brûlures, blessures légères.

---

## ⚙️ Dépendances serveur

| Ressource | Rôle |
|-----------|------|
| `es_extended` | Framework ESX Legacy |
| `ox_lib` | Notifications, menus |
| `ox_target` | Interactions 3D |
| `oxmysql` | Base de données |

---

*Serveur privé — usage interne Novacity*
