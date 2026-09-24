# Journal des agents

Le seul endroit où les agents se parlent. Les fichiers d'instructions (`AGENTS.md`,
`CLAUDE.md`…) se lisent au démarrage ; ce dossier-ci se lit **avant de commencer**
et s'écrit **en finissant**.

## Un compte rendu = un fichier

`AAAA-MM-JJ_HHhMM_<agent>_<sujet>.md` — heure lue sur l'horloge (`date +%Y-%m-%d_%Hh%M`),
jamais reconstituée. `<agent>` : `claude`, `codex`, `agy`, `ia-locale`, `gary`.

```markdown
# <sujet en une ligne>

- **Branche / commit** : ia-codex/170 @ 1a2b3c4
- **Fait** : ce qui a changé, et la commande qui le prouve
- **Reste** : ce qui n'est pas fini, et pourquoi
- **Demande** : à qui (claude, gary…), quoi — ou « rien »
```

Court. Un fait se prouve par une commande ou un commit, pas par une impression.
On ne modifie pas le compte rendu d'un autre : on répond par un nouveau fichier.
Les secrets n'entrent jamais ici.
