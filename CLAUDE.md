# Claude project instructions

Follow [`AGENTS.md`](./AGENTS.md) as the authoritative repository guide.

This is a Git submodule-based orchestration repository, not a monorepo. Work in the relevant child repository for product changes, preserve each child's independent history and remote, then update the root gitlink only after the child commit is pushed. Never track `workspace/`, secrets, environment files, or runtime databases.

Keep Primer, Prelude, and Helix independently runnable. Preserve the Projects → Issues → Helix boundary, with human-controlled implementation and merge transitions. Helix must run from its target repository rather than from the suite launcher.
