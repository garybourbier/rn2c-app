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
- `packaging/fichiers.txt` : les noms des fichiers d'une release, et d'aucun autre endroit ;
  `scripts/fichiers.sh` les lit pour la CI.
- `packaging/mainteneurs.txt` : les comptes qui joignent l'APK signé ;
  `packaging/empreinte-apk.txt` : l'empreinte du certificat qui le signe.
- `packaging/aur/` : le gabarit du paquet AUR `rn2c-bin` ; `packaging/notes-de-version.md` : le
  gabarit des notes de release.

## Pour tous, sans exception
- **Aucun secret dans le dépôt** : ni keystore, ni APK signé, ni mot de passe, ni jeton, ni
  clé. `*.keystore`, `*.jks`, `*.p12`, `*.pk8`, `*.pem`, `key.properties`,
  `keystore.properties`, `*.apk`, `*.idsig` sont dans `.gitignore` — on ne les en retire jamais,
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
- La CI ne construit que sur une étiquette `vX.Y.Z` poussée, qui prépare une release en
  brouillon, ou lancée à la main, qui construit sans créer de release. Elle n'a aucun cache.
  Chaque fichier de bureau du brouillon porte une attestation de provenance. Une release qui
  existe déjà pour l'étiquette, brouillon compris, arrête le run : la supprimer avant de relancer.
- Le numéro de l'appli est celui du serveur RN2C : `scripts/version.sh X.Y.Z`, puis la même
  étiquette que le serveur. L'étiquette se pose sur un commit de `master`.
- `master` reçoit un commit du robot à chaque publication (`releases/latest.json`) : une
  branche de travail fusionne `origin/master` avant la version suivante, et `master` n'est jamais
  réaligné de force.
- L'APK sort de la CI **non signé** : la clé de signature n'entre jamais sur GitHub. Il se
  télécharge depuis le run de l'**étiquette**, son numéro se vérifie (`aapt dump badging`) avant
  la signature, et l'APK signé est joint au brouillon par un compte de `packaging/mainteneurs.txt`.
  La CI joint elle-même le relevé de son contenu (`rn2c-vX.Y.Z-contenu-apk.txt`) : l'APK signé ne
  peut en différer que par ses fichiers de signature.
- Avant de publier : écrire, avant le premier titre des notes, ce que la version change, et
  pousser le paquet AUR `rn2c-bin`, dont le nom appartient au compte AUR d'un mainteneur.
  `latest-json.yml` refuse une release incomplète, un fichier joint par la CI sans attestation du
  run de release.yml sur le commit de l'étiquette, un APK d'un autre certificat, d'un autre numéro
  ou d'un autre contenu que le relevé ; il se relance à la main une fois la release complétée.
- `latest.json` porte toujours la plus haute release publiée de la forme `vX.Y.Z`, même plus basse
  que la précédente : pour **retirer** une release, la supprimer (ou la repasser en préversion),
  puis relancer `latest-json.yml` à la main.
- Aucune ref ne s'appelle `main` ni `main/…` : les 0.2.x y cherchent leur mise à jour, et
  `latest-json.yml` s'arrête si l'une existe.
- Une étiquette ne se pose **que sur un commit de `master`** : le workflow qui tourne est celui du
  commit étiqueté, et la garde « sur master » vit dans ce même fichier. Posée sur le commit d'une
  demande de fusion, l'étiquette ferait tourner le workflow de son auteur avec le jeton du dépôt.
- Le brouillon attend le job Android de son run, qui produit l'APK non signé et le relevé de son
  contenu : la publication exige les deux, une panne de la chaîne Android retient donc aussi les
  fichiers de bureau.
- Le paquet AUR se pousse avant la publication : un brouillon reconstruit change les sommes des
  `.deb`, et le paquet refuse de s'installer jusqu'à ce qu'il soit poussé de nouveau.
- Le nom `garybourbier/rn2c-app` est écrit dans les applis installées, et `latest.json` n'est pas
  signé : **ne jamais renommer le compte ni le dépôt** sans avoir d'abord publié une version qui
  lit le nouveau nom. Un nom libéré pourrait être repris par un tiers, qui proposerait ses
  fichiers à toutes ces applis.
- Ces contrôles vivent dans le dépôt : un compte qui peut écrire peut aussi les modifier, et un
  fichier remplacé après la publication n'est revu qu'à la publication suivante. Les mainteneurs,
  et les jetons qu'ils prêtent, sont de confiance.

## Qui fait quoi

| Agent | Il touche | Il ne touche pas |
|---|---|---|
| Claude | tout, dont `tor_proxy.rs` et la sécurité réseau | les secrets de signature |
| `ai agent` (opencode), IA locale | l'interface, les tâches cadrées demandées par Gary | `tor_proxy.rs`, les dépendances réseau, la signature, les releases, `.github/workflows/`, `scripts/`, `packaging/` : la CI est le mécanisme de publication |

Ce qui touche Tor, le proxy ou l'anonymat s'arrête et s'écrit au journal « à confier à Claude ».
