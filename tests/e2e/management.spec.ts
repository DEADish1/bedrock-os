import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const now = 1_788_000_000;
const feeds: Record<string, object> = {
  '/api/v1/dashboard': { schema: 1, partial: false, components: {
    hardware: { status: 'available', data: { logical_processors: 8, memory_total_bytes: 17_179_869_184 } },
    storage: { status: 'available', data: { overall: 'healthy', disk_count: 2 } },
    vms: { status: 'available', data: { running: 0, total: 0 } },
    updates: { status: 'available', data: { status: 'current' } },
  } },
  '/api/v1/apps': { schema: 1, apps: [], install_candidates: [] },
  '/api/v1/backups': { schema: 1, plans: [], create_candidates: [] },
  '/api/v1/hardware': { schema: 1, cpu: { architecture: 'x86_64', model: 'Acceptance CPU', logical_processors: 8, sockets: 1, cores_per_socket: 4, threads_per_core: 2, virtualization: 'AMD-V', virtualization_supported: true }, memory: { total_bytes: 17_179_869_184 }, disks: [{ model: 'Acceptance SSD', vendor: 'Bedrock Lab', size_bytes: 1_000_000_000_000, rotational: false, transport: 'nvme', removable: false }], storage_controllers: [{ class: 'NVMe', description: 'Acceptance controller' }], networks: [{ mtu: 1500, state: 'up', link_type: 'ethernet' }], gpus: [], usb_device_count: 0 },
  '/api/v1/vms': { schema: 1, generated_unix: now, domains: [] },
  '/api/v1/virtualization/passthrough-candidates': { schema: 1, gpus: [], usb_devices: [], assignments: [] },
  '/api/v1/images': { schema: 1, images: [], upload_candidates: [] },
  '/api/v1/storage': { schema: 1, generated_unix: now, overall: 'healthy', disks: [], disk_candidates: [], managed_pools: [], software_raid: { md_arrays: [], zfs: { available: true, pools: [] } }, hardware_raid: { controller_count: 0, full_visibility_count: 0, attention_count: 0 } },
  '/api/v1/remote/devices': { schema: 1, devices: [], pending_requests: [] },
  '/api/v1/tasks': { schema: 1, generated_unix: now, tasks: [] },
  '/api/v1/alerts': { schema: 1, generated_unix: now, attention_required: false, alerts: [] },
  '/api/v1/audit': { schema: 1, events: [] },
  '/api/v1/settings': { schema: 1, updates: { automatic_checks: true, setup_choice_recorded: true, channel: 'stable', automatic_install: false }, telemetry_enabled: false },
  '/api/v1/users': { schema: 1, users: [], groups: [] },
};

async function mockAuthenticatedApi(page: Page) {
  await page.route('**/api/v1/**', async route => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() !== 'GET') {
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ schema: 1, request_id: request.headers()['idempotency-key'], status: 'succeeded', replayed: false }) });
      return;
    }
    const body = feeds[path];
    await route.fulfill({ status: body ? 200 : 404, contentType: 'application/json', headers: path === '/api/v1/settings' ? { ETag: '"sha256-acceptance-settings"' } : {}, body: JSON.stringify(body ?? { schema: 1, error: 'not-found' }) });
  });
}

async function connect(page: Page) {
  await mockAuthenticatedApi(page);
  await page.goto('/');
  await page.waitForLoadState('networkidle');
  await page.getByLabel('API token').pressSequentially('acceptance-token');
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await expect(page.getByText('Connected to Bedrock', { exact: true })).toBeVisible();
}

async function expectNoAutomatedWcagViolations(page: Page) {
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
  expect(results.violations, results.violations.map(item => `${item.id}: ${item.help}`).join('\n')).toEqual([]);
}

test('authentication entry is keyboard reachable and meets automated WCAG A/AA checks', async ({ page }) => {
  await page.goto('/');
  await page.waitForLoadState('networkidle');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button', { name: 'Bedrock home' })).toBeFocused();
  await expectNoAutomatedWcagViolations(page);
});

test('every management area is keyboard navigable and meets automated WCAG A/AA checks', async ({ page }) => {
  test.setTimeout(120_000);
  await connect(page);
  const areas = ['Overview', 'Virtual machines', 'Storage', 'Image library', 'Apps', 'Backup', 'Activity', 'Remote access', 'Users', 'Hardware', 'Project status', 'Settings', 'Help'];
  for (const area of areas) {
    const control = page.locator('aside').getByRole('button', { name: area });
    await control.focus();
    await page.keyboard.press('Enter');
    await expect(control).toHaveClass(/active/);
    await expectNoAutomatedWcagViolations(page);
  }
});

test('an authenticated settings mutation sends guarded input and refreshes confirmed state', async ({ page }) => {
  let mutation: { headers: Record<string, string>; body: object } | undefined;
  await connect(page);
  await page.route('**/api/v1/settings', async route => {
    const request = route.request();
    if (request.method() === 'PUT') {
      mutation = { headers: request.headers(), body: request.postDataJSON() };
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ schema: 1, request_id: request.headers()['idempotency-key'], status: 'succeeded', replayed: false }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { ETag: '"sha256-acceptance-settings"' }, body: JSON.stringify(feeds['/api/v1/settings']) });
  });
  await page.getByRole('button', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'Disable', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('Update policy saved');
  expect(mutation?.headers.authorization).toBe('Bearer acceptance-token');
  expect(mutation?.headers['idempotency-key']).toMatch(/^[0-9a-f-]{36}$/);
  expect(mutation?.headers['if-match']).toBe('"sha256-acceptance-settings"');
  expect(mutation?.body).toEqual({ schema: 1, setting: 'automatic_checks', value: false, beta_risk_acknowledged: false });
});

test('advanced details are keyboard operable while primary hardware health stays visible', async ({ page }) => {
  await connect(page);
  await page.locator('aside').getByRole('button', { name: 'Hardware' }).click();
  await expect(page.getByText('8 threads', { exact: true })).toBeVisible();
  await expect(page.getByText('Ready', { exact: true })).toBeVisible();
  const summary = page.locator('summary').filter({ hasText: 'Advanced hardware details' });
  await summary.focus();
  await page.keyboard.press('Enter');
  await expect(summary.locator('..')).toHaveAttribute('open', '');
  await expect(page.getByRole('heading', { name: 'Processor topology' })).toBeVisible();
  await expect(page.getByText('Acceptance controller', { exact: true })).toBeVisible();
  await expect(page.getByText('8 threads', { exact: true })).toBeVisible();
  await expectNoAutomatedWcagViolations(page);
  await page.locator('aside').getByRole('button', { name: 'Storage' }).click();
  const storageSummary = page.locator('summary').filter({ hasText: 'Advanced storage details' });
  await storageSummary.focus();
  await page.keyboard.press('Enter');
  await expect(storageSummary.locator('..')).toHaveAttribute('open', '');
  await expect(page.getByText('Storage health, rebuild state, and destructive warnings remain visible above.')).toBeVisible();
  await expect(page.getByText('healthy', { exact: true }).first()).toBeVisible();
  await expectNoAutomatedWcagViolations(page);
});
