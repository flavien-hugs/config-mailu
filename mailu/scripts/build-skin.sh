#!/bin/sh
# Compile le thème Roundcube SBBS (overrides/roundcube/skins/sbbs), à lancer
# depuis mailu/ après toute modification des fichiers .less :
#
#   ./scripts/build-skin.sh
#
# Les sources d'Elastic sont copiées depuis l'image webmail de compose.yml
# (MAILU_VERSION) : le thème est compilé contre la version de Roundcube
# déployée. La stack n'a pas besoin de tourner ; l'image est téléchargée si
# elle manque.
# Produit styles/styles.min.css, à commiter (le serveur n'a pas besoin de
# Node). Nécessite Node / npx sur la machine qui compile.
set -eu

ENV_FILE=${ENV_FILE:-mailu.env}
SKIN=overrides/roundcube/skins/sbbs

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

image=$(docker compose --env-file "$ENV_FILE" config --images | grep '/webmail:')
docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image"

# Conteneur créé mais jamais démarré, juste pour en copier les fichiers.
# Même arborescence que dans l'image : skins/elastic à côté de skins/sbbs,
# pour que "../../elastic/..." se résolve.
cid=$(docker create "$image")
trap 'docker rm -f "$cid" >/dev/null; rm -rf "$work"' EXIT
docker cp -q "$cid":/var/www/roundcube/skins/elastic "$work/elastic"
cp -R "$SKIN" "$work/sbbs"

# --rewrite-urls=all : les url(../fonts/...) d'Elastic pointent vers
# skins/elastic/..., le thème ne dupliquant ni polices ni images.
npx --yes -p less@4 lessc --rewrite-urls=all \
  "$work/sbbs/styles/styles.less" "$work/styles.css"

# Elastic écrit url('../images/...') dans styles/widgets/*.less en visant
# skins/elastic/images (relatif au CSS final, pas au .less) : lessc le
# réécrit en elastic/styles/images, qu'on corrige.
sed -i.bak 's#\.\./\.\./elastic/styles/images/#../../elastic/images/#g' "$work/styles.css"

# Minification légère (commentaires et blancs), sans dépendance de plus.
npx --yes -p clean-css-cli@5 cleancss -O1 \
  -o "$SKIN/styles/styles.min.css" "$work/styles.css"

echo "Thème compilé : $SKIN/styles/styles.min.css ($(du -h "$SKIN/styles/styles.min.css" | cut -f1))"
