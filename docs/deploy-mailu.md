# Déploiement sur le VPS — sbbs-technology.com

Serveur mail : `mail.sbbs-technology.com`, derrière nginx-proxy + acme-companion
déjà en place sur le VPS. Adresses : `prenom@sbbs-technology.com`.

## 0. Prérequis

- **Port 25 sortant ouvert** chez l'hébergeur. Test depuis le VPS :
  `nc -vz gmail-smtp-in.l.google.com 25`. Bloqué → ouvrir un ticket, sinon
  aucun mail ne part vers l'extérieur.
- **Reverse DNS (PTR)** de l'IP du VPS → `mail.sbbs-technology.com`
  (console de l'hébergeur).
- Docker + Docker Compose v2 récents (`docker compose version`).
- Le dépôt poussé sur un dépôt git **privé**.
- Idéalement, un disque ou volume chiffré pour `~/mailu-stack`.

## 1. DNS

À créer chez le registrar de `sbbs-technology.com` (`IP_DU_VPS` à remplacer) :

| Type | Nom | Valeur |
|---|---|---|
| A | `mail` | `IP_DU_VPS` |
| AAAA | `mail` | IPv6 du VPS (si disponible) |
| MX | `@` | `mail.sbbs-technology.com` — priorité `10` dans son propre champ |
| TXT | `@` | `v=spf1 mx -all` |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@sbbs-technology.com` |
| TXT | `dkim._domainkey` | fourni par Mailu à l'étape 6 |

La plupart des interfaces DNS ont un champ « Priorité » séparé pour le MX :
le contenu est alors le seul nom d'hôte, sans le `10` ni point final.

Si `sbbs-technology.com` a déjà un enregistrement SPF (autre service d'envoi),
fusionner plutôt que d'en créer un second : un seul `v=spf1` par nom.

Vérifier : `dig +short mail.sbbs-technology.com` et
`dig +short MX sbbs-technology.com`.

## 2. Préparer le VPS

```sh
sudo ufw allow 22,80,443,25,465,587,993,995/tcp && sudo ufw enable

git clone <dépôt-privé> ~/mailu-stack
cd ~/mailu-stack/mailu
cp mailu.env.server.example mailu.env && chmod 600 mailu.env
```

Docker contourne `ufw` : les ports 110 / 143 / 4190 et le web du frontal sont
fermés par `mailu.env` (liés à `127.0.0.1`), pas par le pare-feu.

## 3. Relever les infos de nginx-proxy

```sh
docker network ls                                   # -> PROXY_NETWORK
docker network inspect <réseau> -f '{{(index .IPAM.Config 0).Subnet}}'
                                                    # -> REAL_IP_FROM
docker inspect <conteneur-acme-companion> \
  -f '{{range .Mounts}}{{if eq .Destination "/etc/nginx/certs"}}{{.Source}}{{end}}{{end}}'
                                                    # -> FRONT_CERTS_DIR
```

## 4. Compléter `mailu.env`

Tout ce qui concerne `sbbs-technology.com` est déjà rempli. Reste à remplacer
chaque `CHANGE_ME` (l'indication est sur la ligne au-dessus) :

| Variable | Valeur |
|---|---|
| `SECRET_KEY` | `openssl rand -base64 16` |
| `INITIAL_ADMIN_PW` | `openssl rand -hex 16` — à noter |
| `POSTGRES_PASSWORD`, `DB_PW`, `ROUNDCUBE_DB_PW` | `openssl rand -hex 16`, un chacun |
| `PROXY_NETWORK`, `REAL_IP_FROM`, `FRONT_CERTS_DIR` | relevés à l'étape 3 |

Ne jamais réutiliser les secrets du Mac. Contrôle :

```sh
grep -n CHANGE_ME mailu.env        # ne doit plus rien afficher
```

## 5. Démarrer

```sh
export COMPOSE_ENV_FILES=mailu.env
docker compose config | grep -c '^      DOMAIN:'   # attendu : 8
docker compose pull
docker compose up -d
docker compose logs -f front admin antivirus
```

- acme-companion obtient le certificat de `mail.sbbs-technology.com` en 1 à
  2 minutes. En attendant, `front` affiche « Missing cert or key file,
  disabling TLS », puis active le TLS mail seul.
- ClamAV télécharge ses signatures : jusqu'à 10 minutes avant `healthy`.
- Pas de Node sur le serveur : le CSS du thème est déjà compilé.

## 6. Première configuration

Sur <https://mail.sbbs-technology.com/admin>, avec
`admin@sbbs-technology.com` et `INITIAL_ADMIN_PW` :

1. Changer le mot de passe ; activer la 2FA si proposée.
2. **Domaines → sbbs-technology.com → Générer les clés DKIM**, puis publier
   l'enregistrement `dkim._domainkey` affiché dans le DNS.
3. Créer l'alias `postmaster@sbbs-technology.com` → `admin@sbbs-technology.com`
   (reçoit les rapports DMARC ; exigé par les RFC).
4. Créer les comptes, puis un jeton d'authentification par client mail
   (`AUTH_REQUIRE_TOKENS=true` : le mot de passe du compte ne sert qu'au
   webmail).
5. Retirer la valeur de `INITIAL_ADMIN_PW` dans `mailu.env`.

Configuration des clients mail :

| | Serveur | Port | Sécurité |
|---|---|---|---|
| IMAP | `mail.sbbs-technology.com` | 993 | SSL/TLS |
| SMTP | `mail.sbbs-technology.com` | 465 | SSL/TLS (ou 587 STARTTLS) |
| Identifiant | adresse complète | | mot de passe = jeton |

## 7. Vérifier

Depuis une autre machine :

```sh
nmap -p 25,110,143,465,587,993,995,4190,8080 mail.sbbs-technology.com
# ouverts : 25 465 587 993 995 — fermés : 110 143 4190 8080

openssl s_client -connect mail.sbbs-technology.com:993 \
  -servername mail.sbbs-technology.com </dev/null | grep -E "subject=|Verify"
openssl s_client -starttls smtp -connect mail.sbbs-technology.com:587 \
  </dev/null | grep Verify            # Verify return code: 0 (ok)
```

- Envoyer un mail vers Gmail → « Afficher l'original » : SPF, DKIM et DMARC
  à **PASS**.
- <https://www.mail-tester.com> : viser 10/10.
- <https://mxtoolbox.com> : MX, PTR, listes noires.
- Après quelques semaines sans échec dans les rapports DMARC : passer à
  `p=reject`.

## 8. Sauvegardes

Sur le Mac (la clé privée ne va jamais sur le VPS) :

```sh
age-keygen -o ~/sbbs-mail-backup.key    # affiche la clé publique age1...
```

Sur le VPS (`crontab -e`) :

```
30 3 * * * cd ~/mailu-stack/mailu && AGE_RECIPIENT=age1... ./scripts/backup.sh >> backups/backup.log 2>&1
```

Copier `backups/` hors du VPS (rsync, stockage objet) et tester une
restauration une fois (README, « Sauvegardes »).

## 9. Mises à jour

Sur le Mac : changer `MAILU_VERSION` dans `mailu.env.server.example` et
`mailu.env.example`, lancer `./scripts/build-skin.sh`, tester, commiter,
pousser. Sur le VPS :

```sh
cd ~/mailu-stack && git pull
cd mailu && docker compose pull && docker compose up -d
```

Reporter aussi `MAILU_VERSION` dans le `mailu.env` du VPS (non versionné).

## Dépannage

**`Bind for 0.0.0.0:443 failed: port is already allocated`** (ou `:80`)

`front` essaie de publier 80 / 443 sur toutes les interfaces, déjà pris par
nginx-proxy : `FRONT_HTTP_PORT` / `FRONT_HTTPS_PORT` manquent dans `mailu.env`
(valeurs par défaut 80 / 443, prévues pour le local). Typiquement quand
`mailu.env` a été copié depuis `mailu.env.example` au lieu de
`mailu.env.server.example`.

```sh
grep -n '^FRONT_HTTPS\?_PORT' mailu.env
sed -i -e 's/^FRONT_HTTP_PORT=.*/FRONT_HTTP_PORT=127.0.0.1:8080/' \
       -e 's/^FRONT_HTTPS_PORT=.*/FRONT_HTTPS_PORT=127.0.0.1:8443/' mailu.env
docker compose --env-file mailu.env up -d
```

nginx-proxy joint `front` par le réseau Docker (`VIRTUAL_PORT=80`), pas par
ces ports : les lier à `127.0.0.1` ne coupe pas le webmail. Si `8080` / `8443`
sont eux-mêmes pris (`ss -ltnp | grep -E ':8080|:8443'`), choisir d'autres
ports.
