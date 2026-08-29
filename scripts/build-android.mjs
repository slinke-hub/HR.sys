import { existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const projectRoot = resolve(import.meta.dirname, '..');
const mode = process.argv[2] === 'release' ? 'release' : 'debug';
const gradleTask = mode === 'release' ? 'bundleRelease' : 'assembleDebug';

function firstDirectory(parent) {
  if (!existsSync(parent)) return null;
  const entry = readdirSync(parent, { withFileTypes: true }).find((item) => item.isDirectory());
  return entry ? resolve(parent, entry.name) : null;
}

const localJava = firstDirectory(resolve(projectRoot, '.tools', 'jdk21'));
const localSdk = resolve(projectRoot, '.android-sdk');
const localAndroidHome = resolve(projectRoot, '.android-home');
const localGradleHome = resolve(projectRoot, '.gradle-cache');

const env = {
  ...process.env,
  JAVA_HOME: localJava || process.env.JAVA_HOME,
  ANDROID_HOME: existsSync(localSdk) ? localSdk : process.env.ANDROID_HOME,
  ANDROID_SDK_ROOT: existsSync(localSdk) ? localSdk : process.env.ANDROID_SDK_ROOT,
  ANDROID_USER_HOME: localAndroidHome,
  GRADLE_USER_HOME: localGradleHome,
};

if (!env.JAVA_HOME || !existsSync(env.JAVA_HOME)) {
  throw new Error('JDK 21 was not found. Install it or set JAVA_HOME before building Android.');
}

if (!env.ANDROID_HOME || !existsSync(env.ANDROID_HOME)) {
  throw new Error('Android SDK was not found. Install it or set ANDROID_HOME before building Android.');
}

const sync = spawnSync('npm.cmd', ['run', 'mobile:sync'], {
  cwd: projectRoot,
  env,
  stdio: 'inherit',
  shell: true,
});

if (sync.status !== 0) process.exit(sync.status ?? 1);

const gradle = spawnSync('gradlew.bat', [gradleTask], {
  cwd: resolve(projectRoot, 'android'),
  env,
  stdio: 'inherit',
  shell: true,
});

process.exit(gradle.status ?? 1);
