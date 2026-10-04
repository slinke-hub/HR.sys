/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/crm-dashboard.jsx'],
  prefix: 'tw-',
  important: true,
  corePlugins: { preflight: false },
  theme: {
    extend: {
      colors: {
        ink: 'var(--color-text-primary)',
        canvas: 'var(--color-bg-base)',
        brand: 'var(--color-primary)',
        mint: 'var(--color-success)'
      },
      boxShadow: {
        panel: 'var(--shadow-sm)',
        float: 'var(--shadow-md)'
      }
    }
  },
  plugins: []
};
