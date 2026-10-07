# Switcher — ⌘Tab fenêtre par fenêtre pour macOS

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Switcher" />
</p>

Switcher remplace le ⌘Tab de macOS par un sélecteur **par fenêtre**, comme Alt-Tab sous Windows. Le brouillon Thunderbird et la boîte de réception ont chacun leur carte, et chaque fenêtre Chrome aussi. Le design est celui de Stack : verre dépoli sombre, coins arrondis, dégradé de la couleur d'accent.

## Fonctionnalités

- **Une carte par fenêtre**, avec un aperçu, l'icône de l'app et le titre complet de la fenêtre sélectionnée.
- **Ordre d'utilisation récente** : le premier ⌘Tab va sur la fenêtre précédente.
- **Fenêtres réduites, apps masquées et apps sans fenêtre** restent accessibles, avec un badge.
- **Navigation** : Tab / ⇧Tab, flèches, survol et clic à la souris. Relâcher ⌘ amène *exactement* la fenêtre choisie au premier plan.
- **Actions** pendant la sélection : `W` ferme la fenêtre (ou le bouton × sur la carte), `Q` quitte l'app, `H` masque l'app, `M` réduit la fenêtre, `Échap` annule.
- **Sécurité** : ⌘Tab revient toujours à macOS quand Switcher s'arrête (fermeture normale, signal, plantage), ou si l'autorisation Accessibilité est retirée.

## Installation

Il faut macOS 14 ou plus récent, et Xcode ou les Command Line Tools (Swift 6).

```bash
./build.sh --install --run
```

Le script compile en Release, assemble `Switcher.app` et le signe localement avec un identifiant stable, pour que les autorisations survivent aux recompilations. Il l'installe ensuite dans `/Applications` et le lance.

## Autorisations

| Autorisation | Rôle | Obligatoire |
|---|---|---|
| Accessibilité | Intercepter ⌘Tab et mettre une fenêtre précise au premier plan | Oui |
| Enregistrement de l'écran | Aperçus des fenêtres | Non (sinon : icônes) |

Tant que l'Accessibilité n'est pas accordée, ⌘Tab garde son comportement macOS habituel. Une fenêtre d'accueil guide la configuration, et l'icône de la barre des menus › *Autorisations…* la rouvre.

## Fonctionnement technique

| Fichier | Rôle |
|---|---|
| `System/NativeCommandTab.swift` | Désactive le ⌘Tab natif (`CGSSetSymbolicHotKeyEnabled`) et le réactive à chaque sortie |
| `System/KeyboardTap.swift` | Filtre clavier de session sur son propre thread : ouvre le sélecteur au ⌘Tab, lit les touches, détecte le relâchement de ⌘ |
| `System/CommandTabHotKeys.swift` | Raccourci global de secours pour les champs de mot de passe (saisie sécurisée) |
| `Windows/WindowList.swift` | Liste les fenêtres via l'API Accessibilité, triées par ordre d'affichage |
| `Windows/WindowActions.swift` | Met au premier plan exactement une fenêtre (méthode d'AltTab / Hammerspoon), ferme, réduit, quitte |
| `Windows/ThumbnailProvider.swift` | Aperçus via ScreenCaptureKit, avec cache |
| `Switcher/SwitcherController.swift` | Logique d'ouverture, de navigation et de validation |
| `UI/` | Panneau et vues SwiftUI |

Diagnostic : `defaults write com.stack.switcher SwitcherDebug -bool true` journalise les délais de chaque ⌘Tab (sous-système `com.stack.switcher`).

## Limites connues

- Les fenêtres situées sur un autre bureau (Spaces) peuvent ne pas apparaître.
- Dans un champ de mot de passe, seuls Tab et ⇧Tab fonctionnent.
