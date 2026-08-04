# Acme Software Factory

Acme Software Factory is a local-first, executable reference architecture made from independent products that cover identity, organizational knowledge, project inception, agent-driven implementation, issue and review management, feature exploration, observability, human steering, and experience study. It demonstrates practical working concepts that subject-matter experts can inspect, adapt, and selectively carry into systems tailored to their organizations; it is not an all-inclusive platform or a universal prescription.

This repository is the suite entrypoint. It contains the shared launcher and pins compatible versions of each product as a Git submodule. Every subproject keeps its own repository, history, releases, and standalone development workflow.

![Agentic software development system](./omni-loop.png)

The diagram is the broader direction, not a claim that every loop is automated today. The current suite focuses on inspectable local workflows with explicit human handoffs.

The architecture deliberately favors independently runnable products, explicit ownership boundaries, and replaceable integration contracts. Local operation is the default way to explore and verify the system, not a requirement that every derived production deployment run on one machine.

## Repository structure

| Path | Default port | Intent |
|---|---:|---|
| [`acme-identity`](https://github.com/eimg/acme-identity) | 8316 | Thin suite identity provider: users, sessions, capability roles, and scoped service tokens. |
| [`primer`](https://github.com/eimg/primer) | 8317 | Independent knowledge system for authorized retrieval, inspectable evidence, and cited answers. |
| [`prelude`](https://github.com/eimg/prelude) | 8318 | Independent project-inception workspace that produces bootstrap artifacts for a new codebase. |
| [`helix`](https://github.com/eimg/helix) | 8319 | Independent agent workflow and PR-control plane. It runs inside a target repository. |
| [`acme-issues`](https://github.com/eimg/acme-issues) | 8320 | Local issue, implementation handoff, pull-request evidence, and human merge surface. |
| [`acme-projects`](https://github.com/eimg/acme-projects) | 8321 | Local feature-exploration board that hands ready work to Acme Issues. |
| [`acme-obs`](https://github.com/eimg/acme-obs) | 8322 | Cross-cutting read-only operational view across suite workflows and source health. |
| [`acme-steering`](https://github.com/eimg/acme-steering) | 8323 | Cross-cutting local decision inbox and policy-guided human-steering coordinator. |
| [`acme-intel`](https://github.com/eimg/acme-intel) | 8324 | Cross-cutting think-lab that studies suite experience and proposes reviewed findings. |
| [`acme-todo`](https://github.com/eimg/acme-todo) | 8331 | Disposable target application used to exercise Helix and the surrounding workflow. |

The products are deliberately not one application. Primer, Prelude, and Helix remain useful without the Acme suite. Their integrations use replaceable HTTP/auth seams rather than imports from sibling repositories. The `acme-*` services provide local alternatives to external identity, project, and issue platforms and may integrate more closely.

## Current workflow boundaries

There are two related paths:

1. **New project:** optional Primer evidence → Prelude inception → exported bootstrap → Helix creates and initializes a target workspace.
2. **Existing project:** Acme Projects exploration → deliberate Acme Issues handoff → Helix implementation in the target repository → independent review evidence → human merge.

Acme Identity is cross-cutting rather than another step in either path. It supplies shared human sessions and narrowly scoped machine credentials when suite authentication is enabled. Observability, Steering, and Intel are also cross-cutting: each has a distinct purpose and a clean product boundary so an organization can adopt, replace, or omit the idea. In this reference suite they are part of the composed local experience (the launcher starts them), not skippable profile flags. Architecturally they remain non-authoritative: Observability pulls allowlisted facts and never becomes a workflow dependency; Steering coordinates decisions without owning source-domain transitions; Intel proposes findings and does not silently publish into Primer. Source products keep their manual workflows when Steering is unused; the factory does not require Intel to implement or merge work.

The cross-cutting products may project some of the same facts, but they have distinct purposes. **Observability** is the first-slice operational view: allowlisted timelines, typed correlations, and source-health status (richer cost, bottleneck, and chart analysis are direction, not this slice); **Steering** is the deliberately sparse authority inbox for decisions and interventions; **Intel** studies versioned, outcome-linked experience and proposes fresh findings; **Primer** distributes governed organizational knowledge and evidence. Reviewed Intel findings may later be published into Primer or proposed as policy and skill improvements, but Intel does not silently turn hypotheses into organizational truth. In short: Observability explains the factory, Steering governs it, Intel studies how to improve it, and Primer distributes what the organization has responsibly learned.

The first Steering adapter slice is admin-operated and accepts optional, best-effort lifecycle notifications from Prelude, Helix, Issues, and Projects. Informational events enter its local Activity journal; actionable events synchronize decision cases by source revision. Every completed source-backed disposition—human or policy-authorized—is returned to the workflow owner's durable decision ledger and made visible through the owner's existing detail or comment surface without prescribing its next transition. Unavailable decision delivery can be retried explicitly with the same decision ID. Approval can additionally invoke four narrow product-owned actions—Prelude export, Projects submission, Issues triggering, and Helix recovery—through scoped credentials and authoritative receipts. The accepted, reversible Prelude export is the first complete policy-authorized automatic journey; Steering derives its bounded risk assessment, acts under a service principal, and records each lifecycle attempt. Other source actions remain human-authorized. Direct sibling actions still reconcile the case. Background delivery retry, broader risk and automation policies, and workflow-owner routing are deliberately deferred.

Acme Projects does not call Helix directly. A ready card creates a non-triggering Acme Issues issue; a human starts implementation through the configured Issues trigger. Helix reports lifecycle and review evidence back through the service boundaries.

## Clone the complete suite

Clone recursively so Git checks out the commit of every subproject pinned by this repository:

```bash
git clone --recurse-submodules https://github.com/eimg/acme-software-factory.git
cd acme-software-factory
```

If the repository was cloned without submodules, initialize them afterward:

```bash
git submodule update --init --recursive
```

After pulling a newer suite commit, synchronize its pinned subproject versions:

```bash
git pull --recurse-submodules
git submodule update --init --recursive
```

The root repository pins exact commits for reproducible integration. It does not automatically follow the newest `main` of every child repository.

## Install dependencies

Requirements:

- Node.js 22.19 or newer (Node.js 24 LTS is supported)
- npm
- `curl` and `pgrep` for the suite launcher

Install each product independently:

```bash
for project in acme-identity primer prelude helix acme-issues acme-projects acme-obs acme-steering acme-intel acme-todo; do
  npm --prefix "$project" install
done
```

Each subproject README documents its standalone modes, provider configuration, data, and verification commands.

After building Prelude and Steering, verify the **Prelude accepted-export** public-contract journey with isolated temporary state:

```bash
npm --prefix prelude run build
npm --prefix acme-steering run build
node scripts/verify-steering-journey.mjs
```

This is the first complete policy-authorized automatic path: accept a Prelude inception, observe Steering classify and authorize `prelude.package_accepted_export`, and verify the product-owned export plus decision and attempt history over public HTTP. It does not exercise Projects submit, Issues trigger, Helix recover, decision-delivery retry, or `local` auth credentials, and it does not use either product's database or internal modules.

## Start the local services

Run the root launcher:

```bash
./start-acme.sh
```

On an interactive terminal it offers two modes:

- **Off** — seamless feature testing with development-admin access and no sign-in.
- **Local** — Acme Identity sign-in, permission checks, and scoped service-token enforcement.

Unset `ACME_AUTH_MODE` on an interactive terminal shows that menu. Non-interactive runs (no TTY) default to **local** unless you set the variable explicitly—prefer an explicit `ACME_AUTH_MODE=off` or `local` in scripts.

The launcher starts the composed reference suite in dependency order and waits for each health check:

```text
Identity 8316 → Primer 8317 → Prelude 8318 → Issues 8320 → Projects 8321 → Observability 8322 → Steering 8323 → Intel 8324
```

Observability, Steering, and Intel are included here as the reference composition. Their “optional” product stance means clean detachability and non-authority for adapters—not a launcher skip profile.

The launcher supplies default Steering URLs for Prelude, Issues, and Projects, and default study-source URLs for Intel (Observability, Issues, Helix, and Steering). Each of those products' **Connections → Acme Steering** screen shows the effective endpoint, verifies reachability and the product-bound notification credential, and permits a local URL override or a return to the startup setting. Helix is omitted from the launcher; configure Steering from the target repository's `.helix/.env` or Helix **Connections** (including **Use local suite default**). Credentials remain server-side.

Press `Ctrl-C` to stop every service started by the script. For automation, bypass the menu explicitly:

```bash
ACME_AUTH_MODE=off ./start-acme.sh
ACME_AUTH_MODE=local ./start-acme.sh
```

### Suite authentication glossary

The suite uses one operator-facing mode and two adapter styles:

| Concept | Where | Meaning |
|---|---|---|
| `ACME_AUTH_MODE=off` | Identity, Issues, Projects, Observability, Steering, Intel, launcher | Frictionless local admin; no Identity sign-in. Default for interactive exploration when you choose Off. |
| `ACME_AUTH_MODE=local` | Same products + launcher | Shared Identity sessions, permission strings, and scoped service tokens. |
| `*_AUTH_PROVIDER=standalone` | Primer, Prelude, Helix | Product-local principal (no Identity). Launcher sets this when suite mode is `off`. |
| `*_AUTH_PROVIDER=acme-identity` | Primer, Prelude, Helix | Plain-HTTP Identity adapter. Launcher sets this when suite mode is `local`. |

`ACME_AUTH_MODE` and `*_AUTH_PROVIDER` are the same suite choice expressed for two adapter families. Keep them aligned: Identity-backed Prelude with standalone Helix is a common mixed-mode failure (for example Prelude catalog access returning `401`).

Consumers authorize with **permission strings**, not fixed role names. Machine tokens are attached server-side only to explicitly trusted destination origins.

### Provision credentials (local mode)

Before the first local-auth run, provision the suite's scoped machine credentials:

```bash
./start-acme.sh --provision-auth
```

In an interactive local-mode start, the launcher also detects missing credentials and offers to provision them. Non-interactive local startup fails early with the provisioning command when credentials are missing. Ordinary startup never rotates valid tokens; use `--provision-auth` deliberately when credentials expire, are revoked, or need rotation.

The provisioner writes tokens only to ignored local environment files in their intended consumers. It rotates all suite service tokens, so run it before starting services and restart every consumer afterward. Do not commit those files.

For the reference exercise target, Helix-facing tokens are written to `acme-todo/.helix/.env` (Issues, Prelude, and Steering edges). That path is the disposable Todo target used by the suite provisioner—not a claim that Helix can only run there.

### Why Helix is not started by the launcher

Helix resolves its workspace, configuration, and secrets from the current target repository. Start it from the repository it should change, such as Acme Todo:

```bash
cd acme-todo
helix serve
```

Use `helix-dev serve` there when developing the sibling Helix source checkout. Running `npm run dev` inside `helix/` develops Helix itself; it does not attach Helix to another target.

**Other targets:** copy the Helix/Steering token and trusted-origin lines from the provisioned `acme-todo/.helix/.env` into that repository's `.helix/.env` (or run Identity's `npm run provision:suite-auth` after adjusting the provisioner paths for your layout), set `HELIX_AUTH_PROVIDER=acme-identity` when the suite is in `local` mode, and start `helix serve` from that cwd. The ready panel may list Helix's default URL for convenience; the process is not started until you launch it from a target.

Acme Todo is also not started by the suite launcher because it is an example target rather than a key platform service. Start it independently when the exercise needs it:

```bash
npm --prefix acme-todo run dev
```

## Working with subprojects

Commit and push product changes inside the relevant subproject first. The root repository will then show that submodule as pointing at a different commit; commit that pointer update separately when the new product versions are ready to be treated as one compatible suite snapshot.

```text
child repository: implementation + tests + product commit
root repository:  compatible child commit pointers + suite-level docs/scripts
```

This separation lets each product be cloned, versioned, tested, and released independently while the root repository remains a reliable way to reproduce the integrated factory.

## License

The orchestration repository is available under the [MIT License](./LICENSE). Each submodule retains its own license and copyright notices.
