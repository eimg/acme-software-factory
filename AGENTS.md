# Acme Software Factory agent guide

This repository is the orchestration layer for a suite of independent Git repositories. The root owns cross-project documentation, the local launcher, diagrams, and pinned submodule commits. Product implementation belongs in the relevant submodule.

## Architecture stance

- Treat Acme as an executable reference architecture, not an all-inclusive platform or a universal organizational blueprint.
- Preserve local-first operation, independently useful products, explicit ownership, and replaceable public contracts. A production adaptation may be hosted or distributed without weakening those boundaries.
- Prefer a focused working concept that experts can inspect and adapt over speculative breadth intended to cover every organization.
- Do not describe a component as merely a demo or toy; each product should credibly demonstrate its responsibility while remaining clear about current scope.

## Read first

- [`README.md`](./README.md) — product map, boundaries, clone workflow, and launcher usage.
- The target subproject's own `README.md` and `AGENTS.md` before changing that product.
- [`start-acme.sh`](./start-acme.sh) before changing suite startup, ports, authentication modes, or dependency order.

## Product boundaries

- **Acme Identity** is the optional suite identity provider. Consumers authorize with permission strings, not fixed role names.
- **Primer** owns knowledge identities, groups, source-derived metadata, ACLs, retrieval, evidence, and citations. Identity authentication must not replace Primer authorization.
- **Prelude** owns project inception and bootstrap exports. It may query Primer and expose exports to Helix, but must remain independently runnable.
- **Helix** owns agent orchestration, target-repository execution, and independent PR-control evidence. It must remain provider- and tracker-replaceable.
- **Acme Issues** owns concrete issues, implementation triggering, local PR state, review evidence, and the human merge boundary.
- **Acme Projects** owns exploratory collaboration before work becomes an issue. It hands work to Issues and must not trigger Helix directly.
- **Acme Observability** owns the optional read-only operational projection. It pulls allowlisted facts through public APIs and must never become a source dependency or workflow authority.
- **Acme Steering** owns the optional local decision inbox, delegation policies, escalation, and human-steering record. Source products retain domain authority and their existing manual workflows.
- Steering is admin-operated in the current first pass. Do not infer workflow ownership from current roles or resource fields; preserve stable product/resource seams for a later explicit ownership model.
- Steering may invoke only explicit product-owned action keys through action-specific, trusted-origin credentials. The source product must reload live state, enforce its dedicated Steering permission and domain rules, validate the expected revision, and return the authoritative receipt. Source-backed risk is currently unassessed.
- Steering returns every source-backed human disposition through a versioned decision notice. Each source product durably records and acknowledges it, but owns the deterministic workflow response; receipt of a decision must not be confused with application of an action.
- **Acme Todo** is a disposable target, not a suite dependency.
- **`workspace/`** is local scratch space and must never be tracked by the root repository.

## Git and submodule rules

1. Confirm the actual repository root before every Git operation. The root and each submodule have independent histories and remotes.
2. Never commit product source files as ordinary root-repository content. Product directories must remain Git submodules.
3. Make, verify, commit, and push product changes inside the affected submodule first.
4. Update the root gitlink only after the child commit is intentional and available on its remote.
5. Before publishing a root change, verify every submodule is on the expected commit and has no uncommitted work.
6. Do not recursively reset, clean, or switch submodules. Preserve unrelated user work in every repository.
7. Keep GitHub-facing root documentation portable. Do not add machine-specific absolute paths to `README.md`.
8. Never commit `.env`, service tokens, provider keys, SQLite runtime files, or the ignored `workspace/` directory.

## Suite invariants

- Key port order is Identity `8316`, Primer `8317`, Prelude `8318`, Helix `8319`, Issues `8320`, Projects `8321`, Observability `8322`, Steering `8323`.
- Helix is launched from a target repository and is intentionally omitted from `start-acme.sh`.
- Acme Todo uses `8331` and is intentionally not counted as a key platform component.
- `ACME_AUTH_MODE=off` is for frictionless feature testing. `local` is for shared human sessions, permission enforcement, and service-token testing.
- Independent products must retain standalone auth/runtime defaults or replaceable adapters.
- Machine credentials may only be attached server-side to explicitly trusted destination origins.
- Authorization must happen before restricted Primer material enters retrieval candidates, evidence, prompts, answers, or traces.

## Validation

For a subproject change, run that repository's documented verification command. For suite-level changes:

```bash
bash -n start-acme.sh
./start-acme.sh --help
git diff --check
git submodule status --recursive
```

When startup behavior changes, exercise both `off` and `local` selection paths where practical. A root documentation-only change does not require rebuilding every product, but all submodules must still be clean and pinned to remote commits before the root is pushed.
