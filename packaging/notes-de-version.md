RN2C {{VERSION}} — même numéro que le serveur RN2C {{VERSION}}.

## Quel fichier prendre

| Système | Fichier |
|---|---|
| Windows | `RN2C_{{VERSION}}_x64-setup.exe` (installeur), `RN2C_{{VERSION}}_x64_en-US.msi`, ou `rn2c-v{{VERSION}}-portable-win64.zip` sans installation |
| Linux x86_64 | `RN2C_{{VERSION}}_amd64.AppImage`, `RN2C_{{VERSION}}_amd64.deb` ou `RN2C-{{VERSION}}-1.x86_64.rpm` |
| Linux ARM64 | `RN2C_{{VERSION}}_aarch64.AppImage`, `RN2C_{{VERSION}}_arm64.deb` ou `RN2C-{{VERSION}}-1.aarch64.rpm` |
| Arch Linux | le paquet AUR `rn2c-bin` |
| macOS, Intel et Apple Silicon | `RN2C_{{VERSION}}_universal.dmg` |
| Android | `rn2c-v{{VERSION}}-signed.apk` |

## À savoir

- **Android** : l'appli est signée par une nouvelle clé depuis la 0.3.0. Désinstalle d'abord une version 0.2.x, sinon Android refuse l'installation.
- **Windows** : l'appli n'est pas signée. Si Windows affiche « Windows a protégé votre ordinateur », choisis « Informations complémentaires », puis « Exécuter quand même ».
- **macOS** : l'appli n'est pas notarisée par Apple. À la première ouverture, va dans Réglages Système → Confidentialité et sécurité, puis « Ouvrir quand même ».
- Tout le trafic de l'appli passe par Tor, intégré à l'appli : rien d'autre à installer.
