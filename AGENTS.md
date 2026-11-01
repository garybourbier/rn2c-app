# RN2C app — règles communes à tous les agents

Application native de la radio RN2C : Rust + Tauri v2, avec un client Tor embarqué (Arti).
Cibles : Linux x86_64 et ARM64 (AppImage, `.deb`, `.rpm`, AUR), Windows (`.exe`, `.msi`), macOS
(`.dmg` universel), Android (APK).
Ce fichier est la seule source des règles du projet : Claude, Codex, l'IA locale
(`ai agent`, opencode) le lisent tous.

⚠️ **Ce dépôt est PUBLIC.** Tout ce qui est commité ici, ce fichier compris, est lisible par
n'importe qui, historique compris.

## Avant de commencer, en finissant

1. **Avant** : lire les derniers comptes rendus de `docs/agents/journal/`
   (`ls -t docs/agents/journal | head`).
2. **En finissant** : y déposer le sien (format dans `docs/agents/journal/README.md`).
   Le journal est public lui aussi : aucun secret, aucune adresse, aucune identité.

## Ce qui est où
- `src-tauri/src/tor_proxy.rs` : Arti et le proxy local.
  Android : reverse proxy HTTP sur `127.0.0.1:8181` (wry Android ne gère pas `proxy_url`).
  Bureau : SOCKS5 sur `127.0.0.1:19150` + `proxy_url` de la WebView, et un proxy HTTP local
  pour que `getUserMedia` ait un contexte sécurisé.
- `ui/index.html` : l'écran de démarrage (journal Tor en direct).
- `.github/workflows/release.yml` : construit tous les formats ; `latest-json.yml` : met
  `releases/latest.json` à jour quand une release est publiée.
- `scripts/version.sh` : le numéro de l'appli, aux trois endroits qui le portent.
- `packaging/` : le gabarit du paquet AUR `rn2c-bin` et les notes de version.

## Pour tous, sans exception
- **Aucun secret dans le dépôt** : ni keystore, ni APK signé, ni mot de passe, ni jeton, ni
  clé. `*.keystore`, `*.apk`, `*.idsig` sont dans `.gitignore` — on ne les en retire jamais,
  et on ne les force jamais (`git add -f`).
- **Aucune adresse `.onion` d'infrastructure** ajoutée dans un commentaire, un journal ou un
  message de commit. Celle que l'application doit joindre se change sur décision de Gary.
- **Tout le trafic passe par Tor.** Aucune requête réseau hors d'Arti : pas de CDN, pas de
  police distante, pas de télémétrie, pas de résolution DNS en clair. Une dépendance qui
  ouvre une connexion à elle seule est refusée.
- Le micro (`RECORD_AUDIO`) ne sert qu'à la voix Mumble. Aucune lecture du nom du
  périphérique audio : il identifie l'utilisateur.
- Publier une version (étiquette, release, APK distribué) est un acte d'un mainteneur
  (Gary, Pierroons), jamais d'un agent.
- Commentaires et messages de commit en français, au niveau du code voisin.

## Construire
- Bureau : `cargo tauri build` depuis la racine.
- Android : `cargo tauri android build` (SDK + NDK requis ; la signature se fait hors dépôt).
- La CI ne construit que sur une étiquette `vX.Y.Z`, qui prépare une release en brouillon, ou
  lancée à la main, qui construit sans rien publier.
- Le numéro de l'appli est celui du serveur RN2C : `scripts/version.sh X.Y.Z`, puis la même
  étiquette que le serveur.
- L'APK sort de la CI **non signé** : la clé de signature n'entre jamais sur GitHub. L'APK
  signé est joint au brouillon avant sa publication.

## Qui fait quoi

| Agent | Il touche | Il ne touche pas |
|---|---|---|
| Claude | tout, dont `tor_proxy.rs` et la sécurité réseau | les secrets de signature |
| `ai agent` (opencode), IA locale | l'interface, la CI, les tâches cadrées demandées par Gary | `tor_proxy.rs`, les dépendances réseau, la signature, les releases |

Ce qui touche Tor, le proxy ou l'anonymat s'arrête et s'écrit au journal « à confier à Claude ».
