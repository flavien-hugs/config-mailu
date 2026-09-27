#!/bin/sh
# Compile les styles Tailwind de la page de connexion, à lancer depuis mailu/
# après toute modification des classes de overrides/admin/login.html :
#
#   ./scripts/build-login.sh
#
# Produit overrides/admin/sbbs-login.css, à commiter (le serveur n'a pas
# besoin de Node), puis : docker compose restart admin
# Nécessite Node / npx sur la machine qui compile.
set -eu

DIR=overrides/admin
npx --yes tailwindcss@3 \
  -c "$DIR/tailwind/tailwind.config.js" \
  -i "$DIR/tailwind/input.css" \
  -o "$DIR/sbbs-login.css" --minify

echo "Styles compilés : $DIR/sbbs-login.css ($(du -h "$DIR/sbbs-login.css" | cut -f1))"
