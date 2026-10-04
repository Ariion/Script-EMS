# Nova Medical — Démo EMS

Interface de diagnostic médical pour FiveM (ESX Legacy), démo standalone interactive.

## Aperçu

Ce dépôt contient la démo web de l'interface EMS `nova_medical` développée pour le serveur FiveM Novacity.

**[→ Ouvrir la démo](https://anthony-armand.github.io/nova_medical_demo/)** *(après activation de GitHub Pages)*

## Fonctionnalités démontrées

- Panneau médical côté gauche (entre radio HUD et nourriture/boisson)
- Fond semi-transparent — vue sur le patient en jeu
- **6 scénarios patients** : fusillade, accident, couteau, chute, brûlures, blessures légères
- **8 examens médicaux** : évaluation, tension, SpO₂, neuro, ECG, auscultation, glycémie, température
- **ECG animé** en temps réel (normal / tachycardie / fibrillation)
- **3 protocoles** : Bilan ABCDE, Polytraumatisme, Arrêt cardiaque
- Badge d'état patient (Stable / Blessé / Critique)
- Modal de finalisation avec estimation des frais
- Écrans Last Stand et Mort avec compte à rebours
- Toasts de notification

## Stack technique

- FiveM NUI (HTML/CSS/JS vanilla)
- ESX Legacy + ox_lib + ox_target
- Pas de dépendances externes (standalone)

## Structure du script en jeu

```
nova_medical/
├── ui/
│   ├── index.html    # Interface NUI
│   ├── style.css     # Styles (v7)
│   └── script.js     # Logique UI (v15)
├── client/
│   └── main.lua      # Client : debuffs, animations, NUI
├── server/
│   └── main.lua      # Server : examens, facturation
└── shared/
    └── config.lua    # Configuration
```
