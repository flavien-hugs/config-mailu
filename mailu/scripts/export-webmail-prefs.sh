#!/bin/sh
# Exporte les préférences webmail (Roundcube) d'un compte de référence en
# valeurs par défaut pour tous les comptes, à lancer depuis mailu/ :
#
#   ./scripts/export-webmail-prefs.sh                    # compte admin initial
#   ./scripts/export-webmail-prefs.sh prenom@domaine     # autre compte modèle
#
# Produit overrides/roundcube/sbbs-defaults.inc.php (à commiter), copié dans
# le conteneur webmail à chaque démarrage (voir compose.yml) :
#   - s'applique à tous les comptes, existants et futurs, pour chaque
#     réglage qu'ils n'ont pas eux-mêmes modifié ;
#   - chaque utilisateur reste libre de changer ces réglages.
# Appliquer : docker compose --env-file mailu.env up -d --force-recreate webmail
#
# Nécessite la stack démarrée (lecture en base, décodage par le PHP du webmail).
set -eu

ENV_FILE=${ENV_FILE:-mailu.env}
OUT=overrides/roundcube/sbbs-defaults.inc.php

val() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-; }
EMAIL=${1:-$(val INITIAL_ADMIN_ACCOUNT)@$(val INITIAL_ADMIN_DOMAIN)}
DB=$(val ROUNDCUBE_DB_NAME)

compose() { docker compose --env-file "$ENV_FILE" "$@"; }

prefs=$(compose exec -T database psql -U postgres -d "${DB:-roundcube}" -Atc \
  "SELECT preferences FROM users WHERE username = '$(printf %s "$EMAIL" | sed "s/'/''/g")'")
if [ -z "$prefs" ]; then
  echo "Aucune préférence pour $EMAIL (compte inconnu ou jamais connecté au webmail)." >&2
  exit 1
fi

# Décodage (format sérialisé PHP) par le PHP du conteneur webmail. Réglages
# propres à un compte exclus : jeton client, dossiers personnels.
php_code='
$p = unserialize(trim(stream_get_contents(STDIN)));
if (!is_array($p)) { fwrite(STDERR, "Préférences illisibles\n"); exit(1); }
$skip = ["client_hash", "archive_mbox", "drafts_mbox", "sent_mbox", "junk_mbox", "trash_mbox"];
ksort($p);
foreach ($p as $k => $v) {
  if (in_array($k, $skip, true)) continue;
  echo "\$config[" . var_export($k, true) . "] = " . var_export($v, true) . ";\n";
}'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "<?php"
  echo "// Préférences webmail par défaut (Roundcube), exportées du compte"
  echo "// $EMAIL le $(date +%Y-%m-%d) par scripts/export-webmail-prefs.sh."
  echo "// Valeurs par défaut : chaque utilisateur peut les modifier ; un réglage"
  echo "// déjà changé par un utilisateur n'est pas touché. Ne pas éditer à la"
  echo "// main : relancer le script, puis recréer le conteneur webmail."
  echo
  printf %s "$prefs" | compose exec -T webmail php -r "$php_code"
} > "$tmp"
mv "$tmp" "$OUT"
chmod 644 "$OUT"
trap - EXIT

echo "Préférences de $EMAIL exportées : $OUT ($(grep -c '^\$config' "$OUT") réglages)"
