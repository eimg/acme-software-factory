# Claude project instructions

Follow [`AGENTS.md`](./AGENTS.md) as the authoritative repository guide.

This is a Git submodule-based orchestration repository, not a monorepo. Work in the relevant child repository for product changes, preserve each child's independent history and remote, then update the root gitlink only after the child commit is pushed. Never track `workspace/`, secrets, environment files, or runtime databases.

Keep Primer, Prelude, and Helix independently runnable. Preserve the Projects → Issues → Helix boundary and the human merge boundary. Optional Steering may coordinate or invoke only the shipped product-owned action contracts; only the bounded accepted-Prelude export is policy-automated in the current reference configuration. Optional Intel may study allowlisted sibling experience and propose reviewed findings, but must remain propose-only and must not silently publish into Primer. Helix must run from its target repository rather than from the suite launcher.
