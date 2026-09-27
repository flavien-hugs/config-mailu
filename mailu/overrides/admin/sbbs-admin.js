/*
 * Thème SBBS de l'administration Mailu, chargé dans chaque page par
 * overrides/nginx/admin-ui.conf (avant </head>).
 *
 * - Clair / sombre : html[data-theme], depuis le cookie colorMode (partagé
 *   avec la page de connexion et le webmail), sinon réglage du système.
 * - Bouton clair / sombre dans la barre du haut.
 * - Logo SBBS à la place de celui de Mailu (si LOGO_URL n'est pas défini) et
 *   bandeau du logo sans couleur imposée : le thème gère le fond.
 * - « Déconnexion » déplacée en bas du menu latéral.
 */
(function () {
  var root = document.documentElement;
  var m = document.cookie.match(/(?:^|; )colorMode=(dark|light)/);
  var dark = m ? m[1] === 'dark' : window.matchMedia('(prefers-color-scheme: dark)').matches;
  root.setAttribute('data-theme', dark ? 'dark' : 'light');

  var LOGO = 'data:image/svg+xml,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect x="4" y="4" width="40" height="40" rx="10" fill="#673de6"/>' +
    '<path d="M14 16h20v16H14z" fill="none" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/>' +
    '<path d="M14 17l10 8 10-8" fill="none" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/></svg>');

  document.addEventListener('DOMContentLoaded', function () {
    if (!document.body.classList.contains('sidebar-mini')) return; // pas une page AdminLTE

    var brand = document.querySelector('.brand-link');
    if (brand) {
      brand.style.removeProperty('background-color');
      var img = brand.querySelector('img.mailu-logo');
      if (img && /\/static\/mailu\.png$/.test(img.getAttribute('src') || '')) img.src = LOGO;
    }

    // « Déconnexion » en bas du menu latéral, comme dans le webmail.
    var logout = document.querySelector('.main-sidebar .nav-sidebar a[href$="/sso/logout"]');
    var sidebar = document.querySelector('.main-sidebar');
    if (logout && sidebar) {
      var item = logout.closest('li');
      var box = document.createElement('div');
      box.className = 'sbbs-sidebar-bottom';
      var ul = document.createElement('ul');
      ul.className = 'nav nav-pills nav-sidebar flex-column';
      ul.setAttribute('role', 'menu');
      ul.appendChild(item);
      box.appendChild(ul);
      sidebar.appendChild(box);
    }

    var nav = document.querySelector('.main-header .navbar-nav.ml-auto');
    if (!nav) return;
    var li = document.createElement('li');
    li.className = 'nav-item';
    li.innerHTML =
      '<a href="#" class="nav-link sbbs-theme-toggle" role="button" title="Clair / sombre" aria-label="Changer de thème (clair / sombre)">' +
      '<svg class="moon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>' +
      '<svg class="sun" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>' +
      '</a>';
    nav.insertBefore(li, nav.firstChild);
    li.firstChild.addEventListener('click', function (e) {
      e.preventDefault();
      var mode = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', mode);
      document.cookie = 'colorMode=' + mode + '; path=/; max-age=31536000; SameSite=Lax' +
        (location.protocol === 'https:' ? '; Secure' : '');
    });
  });
})();
