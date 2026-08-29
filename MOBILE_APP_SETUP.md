# MUQAM HR Mobile App

MUQAM HR now includes both an installable Progressive Web App (PWA) and a native Android Studio project powered by Capacitor. Both use the same interface, CSS, themes, permissions, authentication, and Supabase database as the desktop version.

## Native Android project

The Android application is located in `android/` and uses the package ID `net.muqam.hr`.

Requirements:

- Android Studio with Android SDK 36
- JDK 21 (Android Studio's bundled JDK is suitable)
- An Android SDK platform and build tools matching API 36

Build workflow:

1. Run `npm install`.
2. Run `npm run mobile:sync` whenever the web app changes.
3. Run `npm run mobile:open` to open the project in Android Studio.
4. For a debug APK, run `npm run mobile:build:debug` after Java and the Android SDK are configured.
5. For a Play Store bundle, configure a release signing key and run `npm run mobile:build:release`.

The generated debug APK will be placed under `android/app/build/outputs/apk/debug/`. Release bundles are placed under `android/app/build/outputs/bundle/release/`.

The packaging script copies only the runtime web application into `www/`; database migrations, development scripts, repository metadata, and dependencies are not embedded in the Android application.

## Deployment requirement

Deploy the site over HTTPS. Service workers and mobile installation require HTTPS in production; `localhost` is allowed during development.

## PWA Android installation

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
