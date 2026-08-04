#!/usr/bin/env node
/**
 * Verifies the Prelude accepted-export Steering journey over public HTTP only.
 *
 * Scope: accept inception → Steering automatic policy → prelude.package_accepted_export
 * applied → export status + decision/attempt history. Does not cover Projects submit,
 * Issues trigger, Helix recover, delivery retry, UI visibility, or ACME_AUTH_MODE=local.
 */

import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const temp = mkdtempSync(join(tmpdir(), "acme-steering-journey-"));
const children = [];

try {
  const [steeringPort, preludePort] = await Promise.all([freePort(), freePort()]);
  const steeringUrl = `http://127.0.0.1:${steeringPort}`;
  const preludeUrl = `http://127.0.0.1:${preludePort}`;

  children.push(start("Steering", join(root, "acme-steering"), {
    ACME_AUTH_MODE: "off",
    ACME_STEERING_DATA_DIR: join(temp, "steering"),
    ACME_STEERING_PRELUDE_URL: preludeUrl,
    ACME_STEERING_PRELUDE_TOKEN: "",
    PORT: String(steeringPort),
  }));
  children.push(start("Prelude", join(root, "prelude"), {
    PRELUDE_AUTH_PROVIDER: "standalone",
    PRELUDE_DATA_DIR: join(temp, "prelude"),
    ACME_STEERING_URL: steeringUrl,
    PORT: String(preludePort),
  }));

  await Promise.all([
    waitFor(`${steeringUrl}/api/health`, (body) => body?.ok === true),
    waitFor(`${preludeUrl}/api/health`, (body) => body?.ok === true),
  ]);

  const inception = await json(`${preludeUrl}/api/inceptions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      name: "Steering reference journey",
      brief: "Prove a bounded policy-authorized export across public product contracts.",
    }),
  }, 201);
  await json(`${preludeUrl}/api/inceptions/${inception.id}/accept`, { method: "POST" }, 200);

  const activity = await waitFor(
    `${steeringUrl}/api/events`,
    (body) => body?.items?.some((event) => event.source?.resourceId === String(inception.id) && event.event?.type === "inception.accepted"),
  );
  const acceptedEvent = activity.items.find(
    (event) => event.source?.resourceId === String(inception.id) && event.event?.type === "inception.accepted",
  );
  const initialDetail = await json(`${steeringUrl}/api/cases/${encodeURIComponent(acceptedEvent.caseId)}`);
  assert.equal(initialDetail.policy.outcome, "automatic", `unexpected policy: ${JSON.stringify(initialDetail.policy)}`);
  const settledDetail = await waitFor(
    `${steeringUrl}/api/cases/${encodeURIComponent(acceptedEvent.caseId)}`,
    (body) => body?.status !== "awaiting_source",
  );
  assert.equal(settledDetail.status, "applied", `automatic action did not apply: ${JSON.stringify(settledDetail.attempts)}`);

  const exported = await waitFor(
    `${preludeUrl}/api/inceptions/${inception.id}`,
    (body) => body?.inception?.status === "exported",
  );
  const cases = await waitFor(
    `${steeringUrl}/api/cases?view=automated`,
    (body) => body?.items?.some((item) => item.sourceRef === `inception:${inception.id}`),
  );
  const item = cases.items.find((candidate) => candidate.sourceRef === `inception:${inception.id}`);
  const detail = await json(`${steeringUrl}/api/cases/${encodeURIComponent(item.id)}`);
  const decisions = await json(
    `${preludeUrl}/api/steering/decisions?resourceType=inception&resourceId=${inception.id}`,
  );

  assert.equal(exported.inception.status, "exported");
  assert.equal(detail.status, "applied");
  assert.equal(detail.policy.outcome, "automatic");
  assert.equal(detail.riskAssessment.level, "low");
  assert.equal(detail.resolvedBy.kind, "service");
  assert.ok(decisions.items.some((decision) => decision.actor.kind === "service" && decision.resolution === "approve"));
  const attemptKinds = new Set(detail.attempts.map((attempt) => attempt.kind));
  for (const required of ["automatic_authorization", "decision_delivery", "action_invocation"]) {
    assert.ok(attemptKinds.has(required), `missing ${required} attempt`);
  }

  console.log("Steering reference journey passed");
  console.log(`  Prelude inception ${inception.id}: accepted -> exported`);
  console.log(`  Steering case ${detail.id}: low risk -> automatic -> applied`);
  console.log(`  Attempts: ${detail.attempts.map((attempt) => attempt.kind).join(", ")}`);
} catch (error) {
  for (const child of children) {
    const output = child.acmeOutput?.join("").trim();
    if (output) console.error(`\n${child.acmeName} output:\n${output}`);
  }
  throw error;
} finally {
  await Promise.all(children.map(stop));
  rmSync(temp, { recursive: true, force: true });
}

function start(name, cwd, extraEnv) {
  const output = [];
  const child = spawn(process.execPath, ["dist/cli.js", "serve"], {
    cwd,
    env: { ...process.env, ...extraEnv },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => output.push(chunk.toString()));
  child.stderr.on("data", (chunk) => output.push(chunk.toString()));
  child.acmeName = name;
  child.acmeOutput = output;
  child.once("exit", (code) => {
    if (code && code !== 0) console.error(`${name} exited ${code}:\n${output.join("").trim()}`);
  });
  return child;
}

async function stop(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolvePromise) => child.once("exit", resolvePromise)),
    new Promise((resolvePromise) => setTimeout(resolvePromise, 2_000)),
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

async function freePort() {
  const server = createServer();
  await new Promise((resolvePromise, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolvePromise);
  });
  const address = server.address();
  assert.ok(address && typeof address === "object");
  await new Promise((resolvePromise, reject) => server.close((error) => error ? reject(error) : resolvePromise()));
  return address.port;
}

async function waitFor(url, predicate, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const body = await json(url);
      if (predicate(body)) return body;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
  }
  throw new Error(`Timed out waiting for ${url}${lastError ? `: ${lastError.message}` : ""}`);
}

async function json(url, init, expectedStatus = 200) {
  const response = await fetch(url, init);
  const body = await response.json().catch(() => undefined);
  if (response.status !== expectedStatus) {
    throw new Error(`${init?.method ?? "GET"} ${url} returned ${response.status}: ${JSON.stringify(body)}`);
  }
  return body;
}
