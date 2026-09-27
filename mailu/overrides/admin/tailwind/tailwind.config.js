// Tailwind des pages SBBS de connexion (overrides/admin/*.html).
// Compilé par scripts/build-login.sh vers overrides/admin/sbbs-login.css.
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: { relative: true, files: ['../*.html'] },
  // Sombre quand <html data-theme="dark"> : posé au chargement par la page
  // (cookie colorMode partagé avec Roundcube, sinon réglage du système).
  darkMode: ['selector', '[data-theme="dark"]'],
  theme: {
    extend: {
      colors: {
        brand: { DEFAULT: '#673de6', 600: '#5530c9', 300: '#b9a6ff' },
        ink: { DEFAULT: '#0c0c14', dark: '#f1f0f7' },
        muted: { DEFAULT: '#5c5a6b', dark: '#a9a6ba' },
        line: { DEFAULT: '#d4d1e0', dark: '#3a3750' },
        card: { dark: '#1b1a26' },
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto', '"Helvetica Neue"', 'Arial', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
