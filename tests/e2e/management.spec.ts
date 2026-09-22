import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

const now = 1_788_000_000;
const feeds: Record<string, object> = {
  "/api/v1/dashboard": {
    schema: 1,
    partial: false,
    components: {
      hardware: {
        status: "available",
        data: { logical_processors: 8, memory_total_bytes: 17_179_869_184 },
      },
      storage: {
        status: "available",
        data: { overall: "healthy", disk_count: 2 },
      },
      vms: { status: "available", data: { running: 0, total: 0 } },
      updates: { status: "available", data: { status: "current" } },
    },
  },
  "/api/v1/apps": { schema: 1, apps: [], install_candidates: [] },
  "/api/v1/backups": { schema: 1, plans: [], create_candidates: [] },
  "/api/v1/hardware": {
    schema: 1,
    cpu: {
      architecture: "x86_64",
      model: "Acceptance CPU",
      logical_processors: 8,
      sockets: 1,
      cores_per_socket: 4,
      threads_per_core: 2,
      virtualization: "AMD-V",
      virtualization_supported: true,
    },
    memory: { total_bytes: 17_179_869_184 },
    disks: [
      {
        model: "Acceptance SSD",
        vendor: "Bedrock Lab",
        size_bytes: 1_000_000_000_000,
        rotational: false,
        transport: "nvme",
        removable: false,
      },
    ],
    storage_controllers: [
      { class: "NVMe", description: "Acceptance controller" },
    ],
    networks: [{ mtu: 1500, state: "up", link_type: "ethernet" }],
    gpus: [],
    usb_device_count: 0,
  },
  "/api/v1/vms": { schema: 1, generated_unix: now, domains: [] },
  "/api/v1/virtualization/passthrough-candidates": {
    schema: 1,
    gpus: [],
    usb_devices: [],
    assignments: [],
  },
  "/api/v1/images": { schema: 1, images: [], upload_candidates: [] },
  "/api/v1/storage": {
    schema: 1,
    generated_unix: now,
    overall: "healthy",
    disks: [],
    disk_candidates: [],
    managed_pools: [],
    software_raid: { md_arrays: [], zfs: { available: true, pools: [] } },
    hardware_raid: {
      controller_count: 0,
      full_visibility_count: 0,
      attention_count: 0,
    },
  },
  "/api/v1/remote/devices": { schema: 1, devices: [], pending_requests: [] },
  "/api/v1/tasks": { schema: 1, generated_unix: now, tasks: [] },
  "/api/v1/alerts": {
    schema: 1,
    generated_unix: now,
    attention_required: false,
    alerts: [],
  },
  "/api/v1/audit": { schema: 1, events: [] },
  "/api/v1/settings": {
    schema: 1,
    updates: {
      automatic_checks: true,
      setup_choice_recorded: true,
      channel: "stable",
      automatic_install: false,
    },
    remote_relay: { configured: false },
    telemetry_enabled: false,
  },
  "/api/v1/users": { schema: 1, users: [], groups: [] },
};

async function mockAuthenticatedApi(page: Page) {
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() !== "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          schema: 1,
          request_id: request.headers()["idempotency-key"],
          status: "succeeded",
          replayed: false,
        }),
      });
      return;
    }
    const body = feeds[path];
    const etag =
      path === "/api/v1/settings"
        ? '"sha256-acceptance-settings"'
        : path === "/api/v1/remote/devices"
          ? '"sha256-acceptance-remote"'
          : path === "/api/v1/apps"
            ? '"sha256-acceptance-apps"'
            : path === "/api/v1/backups"
              ? '"sha256-acceptance-backups"'
              : path === "/api/v1/vms"
                ? '"sha256-acceptance-vms"'
                : path === "/api/v1/storage"
                  ? '"sha256-acceptance-storage"'
                  : path === "/api/v1/images"
                    ? '"sha256-acceptance-images"'
                    : path === "/api/v1/users"
                      ? '"sha256-acceptance-users"'
                      : null;
    await route.fulfill({
      status: body ? 200 : 404,
      contentType: "application/json",
      headers: etag ? { ETag: etag } : {},
      body: JSON.stringify(body ?? { schema: 1, error: "not-found" }),
    });
  });
}

async function connect(page: Page) {
  await mockAuthenticatedApi(page);
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  await page.getByLabel("API token").pressSequentially("acceptance-token");
  await page.getByRole("button", { name: "Connect", exact: true }).click();
  await expect(
    page.getByText("Connected to Bedrock", { exact: true }),
  ).toBeVisible();
}

async function expectNoAutomatedWcagViolations(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(
    results.violations,
    results.violations.map((item) => `${item.id}: ${item.help}`).join("\n"),
  ).toEqual([]);
}

test("authentication entry is keyboard reachable and meets automated WCAG A/AA checks", async ({
  page,
}) => {
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  await page.keyboard.press("Tab");
  await expect(
    page.getByRole("button", { name: "Bedrock home" }),
  ).toBeFocused();
  await expectNoAutomatedWcagViolations(page);
});

test("every management area is keyboard navigable and meets automated WCAG A/AA checks", async ({
  page,
}) => {
  test.setTimeout(120_000);
  await connect(page);
  const areas = [
    "Overview",
    "Virtual machines",
    "Storage",
    "Image library",
    "Apps",
    "Backup",
    "Activity",
    "Remote access",
    "Users",
    "Hardware",
    "Project status",
    "Settings",
    "Help",
  ];
  for (const area of areas) {
    const control = page.locator("aside").getByRole("button", { name: area });
    await control.focus();
    await page.keyboard.press("Enter");
    await expect(control).toHaveClass(/active/);
    await expectNoAutomatedWcagViolations(page);
  }
});

test("an authenticated settings mutation sends guarded input and refreshes confirmed state", async ({
  page,
}) => {
  let mutation: { headers: Record<string, string>; body: object } | undefined;
  await connect(page);
  await page.route("**/api/v1/settings", async (route) => {
    const request = route.request();
    if (request.method() === "PUT") {
      mutation = { headers: request.headers(), body: request.postDataJSON() };
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          schema: 1,
          request_id: request.headers()["idempotency-key"],
          status: "succeeded",
          replayed: false,
        }),
      });
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      headers: { ETag: '"sha256-acceptance-settings"' },
      body: JSON.stringify(feeds["/api/v1/settings"]),
    });
  });
  await page.getByRole("button", { name: "Settings" }).click();
  await page.getByRole("button", { name: "Disable", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("Update policy saved");
  expect(mutation?.headers.authorization).toBe("Bearer acceptance-token");
  expect(mutation?.headers["idempotency-key"]).toMatch(/^[0-9a-f-]{36}$/);
  expect(mutation?.headers["if-match"]).toBe('"sha256-acceptance-settings"');
  expect(mutation?.body).toEqual({
    schema: 1,
    setting: "automatic_checks",
    value: false,
    beta_risk_acknowledged: false,
  });
});

test("relay setup sends guarded settings input without returning the access token", async ({ page }) => {
  await connect(page);
  let mutation: { headers: Record<string, string>; body: Record<string, unknown> } | null = null;
  await page.route("**/api/v1/settings", async (route) => {
    if (route.request().method() === "PUT") {
      mutation = { headers: route.request().headers(), body: route.request().postDataJSON() };
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ schema: 1, request_id: route.request().headers()["idempotency-key"], status: "succeeded", replayed: false }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", headers: { ETag: '"sha256-acceptance-settings"' }, body: JSON.stringify(feeds["/api/v1/settings"]) });
  });
  await page.getByRole("button", { name: "Settings" }).click();
  await page.getByLabel("Relay host").fill("relay.example.test");
  await page.getByLabel("Server route ID").fill("12345678-1234-4123-8123-123456789abc");
  await page.getByLabel("Relay access token").fill("A".repeat(32));
  await page.getByLabel("Remote connection confirmation").fill("CONFIGURE REMOTE RELAY relay.example.test:443 ROUTE 12345678-1234-4123-8123-123456789abc");
  await page.getByRole("button", { name: "Configure", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("Remote connection configured");
  expect(mutation?.headers.authorization).toBe("Bearer acceptance-token");
  expect(mutation?.headers["if-match"]).toBe('"sha256-acceptance-settings"');
  expect(mutation?.body).toEqual({ schema: 1, operation: "configure", host: "relay.example.test", port: 443, server_route: "12345678-1234-4123-8123-123456789abc", token: "A".repeat(32), confirmation: "CONFIGURE REMOTE RELAY relay.example.test:443 ROUTE 12345678-1234-4123-8123-123456789abc" });
  await expect(page.getByLabel("Relay access token")).toHaveValue("");
});

test("VM console authorization is exact, state-bound, and never places its token in an HTTP URL", async ({
  page,
}) => {
  const path = "/api/v1/vms";
  const previous = feeds[path];
  feeds[path] = {
    schema: 1,
    generated_unix: now,
    domains: [
      {
        name: "test-vm",
        state: "running",
        vcpus: 2,
        memory_mib: 4096,
        autostart: false,
        boot_order: ["disk"],
        image_attachments: [],
        network_attachments: [],
        snapshots: [],
        snapshot_count: 0,
      },
    ],
  };
  try {
    let mutation:
      | { url: string; headers: Record<string, string>; body: object }
      | undefined;
    await connect(page);
    await page.route(
      "**/api/v1/vms/test-vm/console-sessions",
      async (route) => {
        const request = route.request();
        mutation = {
          url: request.url(),
          headers: request.headers(),
          body: request.postDataJSON(),
        };
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            schema: 1,
            request_id: request.headers()["idempotency-key"],
            status: "succeeded",
            replayed: false,
            session: {
              token: "a".repeat(64),
              expires_at: 1,
              websocket_path: "/api/v1/vms/test-vm/console",
            },
          }),
        });
      },
    );
    await page
      .locator("aside")
      .getByRole("button", { name: "Virtual machines" })
      .click();
    await page.getByRole("button", { name: "Open console" }).click();
    await page
      .getByRole("dialog")
      .getByRole("textbox")
      .fill("OPEN CONSOLE VM test-vm");
    await page.getByRole("button", { name: "Open protected console" }).click();
    await expect(page.getByRole("alert")).toContainText(
      "invalid console authorization",
    );
    expect(mutation?.headers.authorization).toBe("Bearer acceptance-token");
    expect(mutation?.headers["if-match"]).toBe('"sha256-acceptance-vms"');
    expect(mutation?.headers["idempotency-key"]).toMatch(/^[0-9a-f-]{36}$/);
    expect(mutation?.body).toEqual({
      schema: 1,
      confirmation: "OPEN CONSOLE VM test-vm",
    });
    expect(mutation?.url).not.toContain("a".repeat(64));
  } finally {
    feeds[path] = previous;
  }
});

test("remote pairing approval is bound to the displayed trust state", async ({
  page,
}) => {
  const path = "/api/v1/remote/devices";
  const previous = feeds[path];
  const pairingId = "12345678-1234-4123-8123-123456789abc";
  feeds[path] = {
    schema: 1,
    devices: [],
    pending_requests: [
      { id: pairingId, approved: false, expires_in_seconds: 420 },
    ],
  };
  try {
    let mutationHeaders: Record<string, string> | undefined;
    await connect(page);
    await page.route("**/api/v1/remote/**", async (route) => {
      if (route.request().method() === "POST") {
        mutationHeaders = route.request().headers();
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            schema: 1,
            request_id: mutationHeaders["idempotency-key"],
            status: "succeeded",
            replayed: false,
          }),
        });
        return;
      }
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        headers: { ETag: '"sha256-acceptance-remote"' },
        body: JSON.stringify(feeds[path]),
      });
    });
    await page.getByRole("button", { name: "Remote access" }).click();
    await page.getByRole("button", { name: "Review" }).click();
    await page
      .getByRole("dialog")
      .getByRole("textbox")
      .fill(`APPROVE REMOTE DEVICE ${pairingId}`);
    await page.getByRole("button", { name: "Approve pairing" }).click();
    await expect(page.getByRole("status")).toContainText(
      "Remote pairing approved",
    );
    expect(mutationHeaders?.["if-match"]).toBe('"sha256-acceptance-remote"');
  } finally {
    feeds[path] = previous;
  }
});

test("advanced details are keyboard operable while primary hardware health stays visible", async ({
  page,
}) => {
  await connect(page);
  await page.locator("aside").getByRole("button", { name: "Hardware" }).click();
  await expect(page.getByText("8 threads", { exact: true })).toBeVisible();
  await expect(page.getByText("Ready", { exact: true })).toBeVisible();
  const summary = page
    .locator("summary")
    .filter({ hasText: "Advanced hardware details" });
  await summary.focus();
  await page.keyboard.press("Enter");
  await expect(summary.locator("..")).toHaveAttribute("open", "");
  await expect(
    page.getByRole("heading", { name: "Processor topology" }),
  ).toBeVisible();
  await expect(
    page.getByText("Acceptance controller", { exact: true }),
  ).toBeVisible();
  await expect(page.getByText("8 threads", { exact: true })).toBeVisible();
  await expectNoAutomatedWcagViolations(page);
  await page.locator("aside").getByRole("button", { name: "Storage" }).click();
  const storageSummary = page
    .locator("summary")
    .filter({ hasText: "Advanced storage details" });
  await storageSummary.focus();
  await page.keyboard.press("Enter");
  await expect(storageSummary.locator("..")).toHaveAttribute("open", "");
  await expect(
    page.getByText(
      "Storage health, rebuild state, and destructive warnings remain visible above.",
    ),
  ).toBeVisible();
  await expect(
    page.getByText("healthy", { exact: true }).first(),
  ).toBeVisible();
  await expectNoAutomatedWcagViolations(page);
});
