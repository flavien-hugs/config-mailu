#!/bin/sh
# S'exécute une seule fois, au premier démarrage sur un volume de données vide.
# Crée un rôle + une base pour Mailu (admin) et un pour Roundcube (webmail),
# avec les identifiants de mailu.env.
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-SQL
	CREATE ROLE "$DB_USER" LOGIN PASSWORD '$DB_PW';
	CREATE DATABASE "$DB_NAME" OWNER "$DB_USER";
	CREATE ROLE "$ROUNDCUBE_DB_USER" LOGIN PASSWORD '$ROUNDCUBE_DB_PW';
	CREATE DATABASE "$ROUNDCUBE_DB_NAME" OWNER "$ROUNDCUBE_DB_USER";
SQL
