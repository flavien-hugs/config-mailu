# Config mailu

Stack mail Mailu exécutée en local sur macOS / Docker Desktop, qui sert de
banc d'essai avant un déploiement sur un VPS.

## Organisation

```
mailu/
  compose.yml        définition de la stack (13 services)
  mailu.env          toute la configuration (--env-file) — SECRETS, ignoré par git
  mailu.env.example  modèle sans secrets, versionné
  overrides/         surcharges de config par service, montées en lecture seule
  postgres/initdb/   crée les rôles et bases mailu + roundcube au premier démarrage
  certs/ dkim/       générés à l'exécution (contenu ignoré par git)
  data/ mail/ filter/ redis/ webmail/ clamav/ dav/   état, ignoré par git
```

Deux éléments d'état sont stockés dans des volumes Docker nommés plutôt que
dans des bind mounts, car leur propriétaire doit pouvoir les `chown`, ce qu'un
bind mount macOS refuse : `mailqueue` (file d'attente postfix) et `pgdata`
(PostgreSQL).

La stack se lance toujours en indiquant le fichier d'environnement :

```sh
cd mailu && docker compose --env-file mailu.env up -d
```

`mailu.env` sert alors deux fois :

- `--env-file` remplace les `${...}` de `compose.yml` (`MAILU_VERSION`,
  `FRONT_*`, `PROXY_NETWORK`). Sans lui, compose refuse de démarrer
  (« lancer avec --env-file mailu.env »).
- `env_file:` injecte ses variables dans les conteneurs : `--env-file` ne
  transmet *rien* à l'intérieur d'un conteneur. Le chemin n'est pas écrit en
  dur dans `compose.yml` : il vient de `MAILU_ENV_FILE`, défini dans le
  fichier lui-même. Pour un autre environnement (ex. `prod.env`), passer
  `--env-file prod.env` et y mettre `MAILU_ENV_FILE=prod.env`. Chaque service
  Mailu doit fusionner l'anchor `*env` (`<<: [*restart, *env, ...]` dans
  `compose.yml`). Si un service la perd, la stack démarre quand même, mais ce
  service tourne sans aucune configuration.

Toutes les commandes `docker compose` (y compris `ps`, `logs`, `exec`) ont
besoin de `--env-file`. Pour ne pas le répéter dans un terminal :

```sh
export COMPOSE_ENV_FILES=mailu.env   # depuis mailu/
```

## Base de données

Mailu (`admin`) et Roundcube (`webmail`) stockent leurs données dans PostgreSQL
(le service `database`), chacun dans sa propre base avec son propre rôle,
configurés par les valeurs `DB_*` et `ROUNDCUBE_DB_*` de `mailu.env`. Le script
d'initialisation ne s'exécute que sur un volume `pgdata` vide : après le
premier démarrage, changer un mot de passe dans `mailu.env` demande aussi un
`ALTER ROLE`, ou une remise à zéro du volume :

```sh
cd mailu && docker compose --env-file mailu.env down && docker volume rm mailu_pgdata
```

Ouvrir un shell SQL :

```sh
cd mailu && docker compose --env-file mailu.env exec database psql -U postgres -d mailu
```

## Premier lancement

```sh
cp mailu/mailu.env.example mailu/mailu.env   # puis renseigner les secrets
openssl rand -base64 16                      # -> SECRET_KEY
openssl rand -hex 16                         # -> chaque *_PW / POSTGRES_PASSWORD
docker network create nginx-proxy              # une seule fois, voir « Passage en production »
cd mailu && docker compose --env-file mailu.env up -d
```

Le nom d'hôte web doit être déclaré en local dans `/etc/hosts` :

```
127.0.0.1  mail.localhost.com
```

Le premier démarrage télécharge environ 2 Go d'images. ClamAV télécharge
ensuite sa base de signatures, ce qui prend plusieurs minutes ; `antispam`
démarre tout de suite et journalise des échecs d'analyse tant que `antivirus`
n'est pas prêt. Pour suivre :

```sh
cd mailu && docker compose --env-file mailu.env logs -f front admin antispam
```

## Ports de l'hôte

Chaque port est publié à l'identique sur toutes les interfaces : la stack est
donc joignable depuis le réseau local, pas seulement depuis cette machine.

| Service     | Port | Service     | Port |
|-------------|------|-------------|------|
| http        | 80   | pop3        | 110  |
| https       | 443  | pop3s       | 995  |
| smtp        | 25   | imap        | 143  |
| submissions | 465  | imaps       | 993  |
| submission  | 587  | managesieve | 4190 |

- Administration : <http://mail.localhost.com/admin>
- Webmail : <http://mail.localhost.com/webmail>

Les ports inférieurs à 1024 sont souvent déjà occupés sur un Mac — vérifier
avec `lsof -iTCP:80 -sTCP:LISTEN` avant de démarrer. La plupart des FAI
bloquent aussi le port 25 sortant : les mails vers l'extérieur ne quitteront
pas la machine.

`TLS_FLAVOR=notls` : les ports TLS uniquement (465 / 995 / 993) acceptent une
connexion mais ne peuvent pas terminer la négociation TLS. Tester sur
25 / 587 / 143.

## Test rapide

```sh
nc -z 127.0.0.1 25 && echo "smtp joignable"
curl -sI http://mail.localhost.com/admin | head -1
swaks --to admin@mail.localhost.com --server 127.0.0.1:25    # si swaks est installé
```

Avant chaque démarrage, vérifier que la configuration atteint bien les
conteneurs — une inspection de l'éditeur a déjà supprimé ces lignes sans
prévenir. Cette commande compte les services qui reçoivent réellement
`mailu.env` une fois les anchors résolues par compose :

```sh
cd mailu && docker compose --env-file mailu.env config | grep -c '^      DOMAIN:'   # attendu : 9
```

## Version allégée

ClamAV occupe à lui seul environ 1,5 Go de mémoire. Pour retirer l'antivirus
et l'analyse des macros, modifier **les deux** fichiers ensemble — laisser
`ANTIVIRUS=clamav` alors que le conteneur n'existe plus fait que rspamd met
les mails en attente :

- `mailu.env` : `ANTIVIRUS=none`, `SCAN_MACROS=false`, `FULL_TEXT_SEARCH=off`
- `compose.yml` : supprimer les services `antivirus` et `oletools`, leurs
  entrées `depends_on` dans `antispam`, et les réseaux `clamav` / `oletools`.

## Passage en production

Sur le serveur, Mailu tourne derrière nginx-proxy + acme-companion, déjà en
place. Tout se règle dans le `mailu.env` du serveur ; `compose.yml` ne change
pas.

Le service `front` reçoit `VIRTUAL_HOST`, `VIRTUAL_PORT` et `LETSENCRYPT_HOST`
à partir de `FRONT_VIRTUAL_HOST`, `FRONT_VIRTUAL_PORT` et
`FRONT_LETSENCRYPT_HOST`. Le préfixe `FRONT_` est volontaire : sous leur vrai
nom, `env_file:` les donnerait aux 9 conteneurs Mailu, et nginx-proxy
routerait le domaine vers chacun d'eux. `front` rejoint aussi le réseau de
nginx-proxy (`PROXY_NETWORK`). En local, ce réseau doit exister :
`docker network create nginx-proxy`.

Dans `mailu.env` du serveur :

- Proxy :
  - `FRONT_VIRTUAL_HOST` et `FRONT_LETSENCRYPT_HOST` = le nom public
    (le même que `HOSTNAMES`) ;
  - `FRONT_HTTP_PORT=127.0.0.1:8080` et `FRONT_HTTPS_PORT=127.0.0.1:8443` :
    80 / 443 appartiennent à nginx-proxy ;
  - `PROXY_NETWORK` = le réseau de nginx-proxy (`docker network ls`).
- TLS mail avec le certificat d'acme-companion :
  - `FRONT_CERTS_DIR` = le répertoire des certificats d'acme-companion sur
    l'hôte (pour un volume nommé : `docker volume inspect <volume> -f
    '{{.Mountpoint}}'`) ;
  - `TLS_FLAVOR=mail`, `TLS_CERT_FILENAME=<domaine>/fullchain.pem`,
    `TLS_KEYPAIR_FILENAME=<domaine>/key.pem`. Au premier démarrage, le
    certificat n'existe pas encore : le frontal démarre sans TLS mail puis
    l'active dès qu'acme-companion l'a obtenu.
- Vraie IP des clients web : `REAL_IP_HEADER=X-Forwarded-For` et
  `REAL_IP_FROM` = le sous-réseau de `PROXY_NETWORK`
  (`docker network inspect <réseau> -f '{{(index .IPAM.Config 0).Subnet}}'`).
- `SESSION_COOKIE_SECURE=True`, `WEBSITE=https://...`, le vrai `DOMAIN` /
  `HOSTNAMES`, et de nouveaux `SECRET_KEY`, `INITIAL_ADMIN_PW` et mots de
  passe de base.

Puis publier les enregistrements DNS : A / AAAA, MX, SPF, DKIM, DMARC et PTR.
