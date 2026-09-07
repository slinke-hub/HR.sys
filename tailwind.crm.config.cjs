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
        panel: '0 10px 35px rgba(15, 23, 42, 0.06)',
        float: '0 14px 35px rgba(15, 23, 42, 0.12)'
      }
    }
  },
  plugins: []
};
