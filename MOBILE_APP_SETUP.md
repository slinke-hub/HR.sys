# MUQAM HR Mobile App

MUQAM HR is delivered as one installable Progressive Web App (PWA) for Android and iOS. It uses the same application, permissions, authentication, and Supabase database as the desktop version.

## Deployment requirement

Deploy the site over HTTPS. Service workers and mobile installation require HTTPS in production; `localhost` is allowed during development.

## Android installation

1. Open the deployed MUQAM HR URL in Chrome.
2. Select **Install Mobile App** from the profile menu, or use Chrome's **Install app** option.
3. Confirm installation. MUQAM HR opens as a standalone app from the home screen.

## iPhone and iPad installation

1. Open the deployed MUQAM HR URL in Safari.
2. Tap **Share**.
3. Select **Add to Home Screen** and confirm.

## Mobile behavior

- Phone-safe header and bottom navigation with iOS safe-area support.
- Touch targets are at least 44px and form fields avoid iOS input zoom.
- Mobile modals use the available viewport and keep action buttons reachable.
- The current authenticated page is restored after launch or refresh.
- Dashboard, Tasks, Requests, and Attendance are available as Android app shortcuts.
- The app shell can open without a connection; secure HR records and write actions still require connectivity.
- Online and offline state changes are shown inside the app.

## Release checklist

- Serve `manifest.json`, `sw.js`, and the application from the same HTTPS origin.
- Ensure `sw.js` is served with JavaScript content type and is not redirected.
- Test login, file uploads, camera/location permission prompts, clock-in/out, and downloads on physical Android and iOS devices.
- Keep Supabase CORS and redirect URLs updated with the production HTTPS origin.
