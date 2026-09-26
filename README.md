# Config mailu

Stack mail Mailu exécutée en local sur macOS / Docker Desktop, qui sert de
banc d'essai avant un déploiement sur un VPS.

## Organisation

```
mailu/
  compose.yml        définition de la stack (13 services)
  mailu.env          valeurs de configuration (--env-file) — SECRETS, ignoré par git
  mailu.env.example  modèle sans secrets, versionné
  overrides/         surcharges de config par service, montées en lecture seule
  postgres/initdb/   crée les rôles et bases mailu + roundcube au premier démarrage
  scripts/backup.sh  sauvegarde bases + mails + DKIM + config (voir « Sauvegardes »)
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

`mailu.env` ne contient que des **valeurs**. C'est `compose.yml` qui décide
quel service reçoit quelle variable, dans ses blocs `environment:` :

| Bloc / service      | Variables reçues                                          |
|---------------------|-----------------------------------------------------------|
| `x-mailu-env`       | config Mailu commune (domaine, TLS, limites, web…)        |
| `admin`             | commun + `DB_*` + `INITIAL_ADMIN_*`                       |
| `webmail`           | commun + `ROUNDCUBE_DB_*` + `ROUNDCUBE_PLUGINS`           |
| `front`             | commun + `VIRTUAL_*`, `LETSENCRYPT_HOST`, `TLS_*_FILENAME`|
| `fetchmail`         | commun + `FETCHMAIL_DELAY`                                |
| `resolver`, `imap`, `smtp`, `antispam` | commun seulement                       |
| `database`          | `POSTGRES_PASSWORD`, `DB_*`, `ROUNDCUBE_DB_*` (aucune config Mailu) |

Dans ces blocs :

- `VAR:` sans valeur reprend `VAR` de `mailu.env`. Absente de `mailu.env`,
  elle n'est pas définie dans le conteneur et Mailu applique sa valeur par
  défaut.
- `${VAR:?...}` est obligatoire (`SECRET_KEY`, `DOMAIN`, `HOSTNAMES`, mots de
  passe) : compose refuse de démarrer si elle manque.
- Ajouter une variable dans `mailu.env` ne suffit pas : il faut aussi la
  déclarer dans le bon bloc de `compose.yml`, sinon aucun conteneur ne la voit.

Pour un autre environnement, il suffit d'un autre fichier de valeurs :
`docker compose --env-file prod.env up -d`.

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

En local, chaque port est publié à l'identique sur toutes les interfaces : la
stack est donc joignable depuis le réseau local, pas seulement depuis cette
machine. Chaque port mail est une variable de `mailu.env` (`SMTP_PORT`,
`IMAP_PORT`…) au format `[ip:]port`, pour pouvoir en fermer sur le serveur
(voir « Sécurité »).

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
prévenir. Cette commande compte les services qui reçoivent réellement la
config Mailu commune une fois les anchors résolues par compose :

```sh
cd mailu && docker compose --env-file mailu.env config | grep -c '^      DOMAIN:'   # attendu : 8
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

`VIRTUAL_HOST`, `VIRTUAL_PORT` et `LETSENCRYPT_HOST` ne sont transmis qu'au
service `front` : nginx-proxy ne route le domaine que vers lui. `front` rejoint aussi le réseau de
nginx-proxy (`PROXY_NETWORK`). En local, ce réseau doit exister :
`docker network create nginx-proxy`.

Dans `mailu.env` du serveur :

- Proxy :
  - `VIRTUAL_HOST` et `LETSENCRYPT_HOST` = le nom public
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
- Les réglages de la section « Sécurité » ci-dessous.

Puis publier les enregistrements DNS : A / AAAA, MX, SPF (`-all`), DKIM,
DMARC (`p=quarantine`, puis `p=reject`) et PTR.

## Sécurité

### Ports exposés

Docker publie ses ports en contournant `ufw` : un port publié est ouvert même
si le pare-feu le refuse. C'est donc dans `mailu.env` qu'on ferme. Sur le
serveur, ne garder publics que 25, 465, 587, 993 (et 995 si POP3) :

```
POP3_PORT=127.0.0.1:110          # POP3 en clair
IMAP_PORT=127.0.0.1:143          # IMAP en clair
SIEVE_PORT=127.0.0.1:4190        # ManageSieve, sauf si les clients s'en servent
PORTS=25,80,443,465,587,993,995  # ports écoutés par front
FRONT_HTTP_PORT=127.0.0.1:8080   # web joignable seulement via nginx-proxy
FRONT_HTTPS_PORT=127.0.0.1:8443
```

Vérifier depuis une autre machine : `nmap -p 25,110,143,465,587,993,995,4190,8080 <ip>`.

### Authentification

- `REAL_IP_HEADER=X-Forwarded-For` et `REAL_IP_FROM` (voir « Passage en
  production ») : sans eux, la limitation par IP voit tout le monde avec
  l'IP de nginx-proxy.
- `AUTH_RATELIMIT_IP` / `AUTH_RATELIMIT_USER` : échecs tolérés avant blocage.
- `AUTH_REQUIRE_TOKENS=true` : les clients IMAP / SMTP utilisent un jeton
  créé dans l'admin (révocable) au lieu du mot de passe du compte.
- Activer la double authentification (2FA) sur le compte admin si la version
  de Mailu la propose.
- `API=false` tant que l'API n'est pas utilisée.
- `/admin` est public derrière nginx-proxy : le restreindre (IP ou
  authentification HTTP) dans la configuration de nginx-proxy, ou au moins
  changer `WEB_ADMIN`.

### TLS sortant

`OUTBOUND_TLS_LEVEL=encrypt` refuse d'envoyer vers un serveur qui ne chiffre
pas ; vide, le chiffrement est opportuniste (plus compatible).

### Secrets

- `chmod 600 mailu.env` sur le serveur.
- Ne jamais réutiliser les secrets locaux ; tous les régénérer.

### Images

`MAILU_VERSION`, `redis` et `postgres` sont épinglés à une version exacte :
une mise à jour est un changement volontaire (et commité). Suivre les
versions de Mailu : <https://github.com/Mailu/Mailu/releases>. Changer de
version majeure de PostgreSQL (16 → 17) demande un dump / restore.

## Sauvegardes

```sh
cd mailu && ./scripts/backup.sh
```

Crée `backups/mailu-<date>.tar` avec les dumps des bases `mailu` et
`roundcube`, et `mail/`, `dkim/`, `dav/` et `mailu.env`. Les archives de plus
de 14 jours sont supprimées (`RETENTION_DAYS`). Avec `AGE_RECIPIENT=<clé
publique age>`, l'archive est chiffrée (`.tar.age`) : indispensable dès
qu'elle quitte le serveur, puisqu'elle contient les secrets et les mails.

Exemple de cron quotidien sur le serveur :

```
30 3 * * * cd /chemin/vers/mailu && AGE_RECIPIENT=age1... ./scripts/backup.sh >> backups/backup.log 2>&1
```

Restauration (stack arrêtée sauf `database`) :

```sh
tar xf mailu-<date>.tar                          # après `age -d` si chiffrée
tar xzf files.tar.gz -C mailu/                   # mail/ dkim/ dav/ mailu.env
docker compose --env-file mailu.env exec -T database \
  pg_restore -U postgres -d mailu --clean --if-exists < db/mailu.dump
docker compose --env-file mailu.env exec -T database \
  pg_restore -U postgres -d roundcube --clean --if-exists < db/roundcube.dump
```

Tester une restauration au moins une fois, sur une autre machine.
