#!/bin/sh
# Sauvegarde de la stack Mailu, à lancer depuis mailu/ :
#
#   ./scripts/backup.sh
#
# Produit une archive unique dans $BACKUP_DIR contenant :
#   - db/mailu.dump, db/roundcube.dump : pg_dump (format custom)
#   - files.tar.gz : mail/, dkim/, dav/ et le fichier d'environnement
#
# Variables (toutes optionnelles) :
#   ENV_FILE        fichier passé à --env-file       (défaut : mailu.env)
#   BACKUP_DIR      répertoire de destination        (défaut : ./backups)
#   RETENTION_DAYS  archives plus anciennes supprimées (défaut : 14)
#   AGE_RECIPIENT   clé publique age : chiffre l'archive (fortement conseillé
#                   dès qu'elle quitte le serveur)
#
# Les fichiers sont lus via un conteneur, car mail/ appartient aux
# utilisateurs des conteneurs et n'est pas lisible par l'utilisateur courant.
set -eu

ENV_FILE=${ENV_FILE:-mailu.env}
BACKUP_DIR=${BACKUP_DIR:-./backups}
RETENTION_DAYS=${RETENTION_DAYS:-14}
AGE_RECIPIENT=${AGE_RECIPIENT:-}

umask 077
stamp=$(date +%Y%m%d-%H%M%S)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$BACKUP_DIR" "$work/db"

compose() { docker compose --env-file "$ENV_FILE" "$@"; }

echo "Dump PostgreSQL..."
for db in $(grep -E '^(DB_NAME|ROUNDCUBE_DB_NAME)=' "$ENV_FILE" | cut -d= -f2); do
  compose exec -T database pg_dump -U postgres -Fc "$db" > "$work/db/$db.dump"
done

echo "Archive des fichiers..."
docker run --rm -v "$PWD":/src:ro alpine:3 \
  tar czf - -C /src mail dkim dav "$ENV_FILE" > "$work/files.tar.gz"

out="$BACKUP_DIR/mailu-$stamp.tar"
tar cf "$out" -C "$work" db files.tar.gz

if [ -n "$AGE_RECIPIENT" ]; then
  age -r "$AGE_RECIPIENT" -o "$out.age" "$out"
  rm "$out"
  out="$out.age"
fi

find "$BACKUP_DIR" -name 'mailu-*.tar*' -mtime +"$RETENTION_DAYS" -delete

echo "Sauvegarde : $out ($(du -h "$out" | cut -f1))"
