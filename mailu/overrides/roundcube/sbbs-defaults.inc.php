<?php
// Préférences webmail par défaut (Roundcube), exportées du compte
// admin@mail.localhost.com le 2026-09-27 par scripts/export-webmail-prefs.sh.
// Valeurs par défaut : chaque utilisateur peut les modifier ; un réglage
// déjà changé par un utilisateur n'est pas touché. Ne pas éditer à la
// main : relancer le script, puis recréer le conteneur webmail.

$config['archive_type'] = 'month';
$config['autoexpand_threads'] = 1;
$config['check_all_folders'] = true;
$config['compose_extwin'] = 0;
$config['compose_save_localstorage'] = 1;
$config['default_charset'] = 'UTF-8';
$config['dsn_default'] = false;
$config['lock_special_folders'] = true;
$config['mdn_default'] = false;
$config['message_extwin'] = 1;
$config['message_show_email'] = true;
$config['message_sort_col'] = 'arrival';
$config['prefer_html'] = false;
$config['spellcheck_before_send'] = true;
