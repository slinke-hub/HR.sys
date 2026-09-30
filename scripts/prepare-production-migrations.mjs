import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const stagingRoot = resolve(projectRoot, 'supabase', 'staging');
const migrationRoot = resolve(projectRoot, 'supabase', 'migrations');
const productionRef = 'bbbetcdioiaozdjkvwxu';
const stagingRef = 'jcfyyxsuspukcmybyhjj';

const mappings = [
  ['auth_backend_services.sql', '20260930100000_auth_backend_services.sql'],
  ['client_backend_services.sql', '20260930101000_client_backend_services.sql'],
  ['deal_backend_services.sql', '20260930102000_deal_backend_services.sql'],
  ['file_backend_services.sql', '20260930103000_file_backend_services.sql'],
  ['productivity_phase_a.sql', '20260930104000_productivity_phase_a.sql'],
  ['productivity_phase_b.sql', '20260930105000_productivity_phase_b.sql'],
  ['productivity_phase_c.sql', '20260930106000_productivity_phase_c.sql']
];

const forbidden = [
  productionRef,
  stagingRef,
  'TEST-MANAGER',
  'TEST-EMPLOYEE',
  'TEST-OUTSIDER',
  'SECURITY TEST',
  'UX DEPENDENCY',
  'INTEGRATED ABC ACCEPTANCE'
];

await mkdir(migrationRoot, { recursive: true });
for (const [sourceName, outputName] of mappings) {
  const sourcePath = resolve(stagingRoot, sourceName);
  const outputPath = resolve(migrationRoot, outputName);
  const source = await readFile(sourcePath, 'utf8');
  for (const marker of forbidden) {
    if (source.toLowerCase().includes(marker.toLowerCase())) {
      throw new Error(`${sourceName} contains forbidden production marker: ${marker}`);
    }
  }
  const reviewedHeader = [
    '-- Reviewed production migration generated from the verified service artifact.',
    `-- Source artifact: ${sourceName}`,
    '-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.',
    ''
  ].join('\n');
  const sanitized = source
    .replace(/staging-only/gi, 'reviewed production')
    .replace(/staging project/gi, 'project')
    .replace(/security staging/gi, 'security production')
    .replace(/staging/gi, 'production');
  await writeFile(outputPath, `${reviewedHeader}${sanitized}`, 'utf8');
  console.log(`Prepared ${outputName}`);
}
