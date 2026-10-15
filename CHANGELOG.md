# Changelog

## [Unreleased]

## [0.3.0] - 2026-10-06

The gem now provisions checkouts that other tools create (herdr, Claude Code, Codex, plain git)
instead of owning the whole flow.

### Added

- `worktree init [name] [--level minimal|test|full] [--seed] [--base REF] [--force]` provisions the
  current linked worktree and is safe to repeat. `minimal` copies configuration and links `node_modules`,
  `test` adds the configured `test_command` or an own test database, `full` adds own databases.
- `.worktree.yml` project configuration: copy list, directories, touch files, node_modules mode,
  database variables, template cloning and the test command.
- `worktree install` and the installer write `.worktreeinclude` (Claude Code), a marked `## Worktrees`
  block in `AGENTS.md`/`CLAUDE.md`, and a herdr plugin under `.worktree/herdr/` that runs
  `init --level minimal` on `worktree.created`.
- The development database is cloned from the main one with `CREATE DATABASE ... TEMPLATE` on
  PostgreSQL, capped by `database.template_max_gb` (default 5), with a schema-load fallback.
  Seeding is opt-in with `--seed`.

### Changed

- **Breaking:** database names are written to `.env.development.local` and `.env.test.local` as
  `DATABASE_NAME` (configurable) instead of `DATABASE_NAME_DEVELOPMENT`/`DATABASE_NAME_TEST` in `.env`,
  and `config/database.yml` is copied unchanged.
- **Breaking:** `init` no longer runs `bin/setup`, migrations or seeds by default.
- **Breaking:** `close` drops only the databases recorded in the worktree's `.env.*.local` files.
  Worktrees created by 0.2 keep their databases; drop them by hand.
- Worktree names are sanitized to `[A-Za-z0-9_]` in database names.
- `node_modules` is symlinked to the main checkout by default instead of copied.
- `create NAME BASE` is the explicit form of the previous default command and takes `--level` and `--seed`.
- Requires Ruby 3.0 or newer.

### Removed

- `--skip-seeds` (accepted and ignored; seeding is now opt-in).

## [0.2.0] - 2026-09-26

### Added

- `worktree exec -- COMMAND` and `worktree verify` enforce the recorded branch/base and worktree-local Bundler context.
- Worktree creation records its base in private Git metadata and installs a chaining pre-push verifier.
- A shared launcher generator pins `BUNDLE_GEMFILE` before Ruby startup; `worktree:install FORCE=1` upgrades existing launchers.

### Fixed

- Database name double-substitution when worktree name starts with "test" (e.g. `app_test-worktree_test-worktree_development`). Replaced sequential `gsub!` calls with single-pass `Regexp.union` replacement
- Database drop during close now uses `bin/rails db:drop` instead of bare `dropdb`, picking up connection settings from `database.yml`
- Worktree init now copies `config/master.key` and all files under `config/credentials/` from the main worktree, picking up env-specific keys like `test.key`/`test.yml.enc` instead of only `development.key`

### Changed

- **Breaking:** creation requires an explicit base (`worktree feature origin/main`) instead of inheriting the current branch.

- Worktrees are now created inside `.worktrees/` in the project root instead of as sibling directories. This preserves tool config (mise, Claude Code, etc.) that depends on being inside the project tree
- `.worktrees` is automatically added to `.gitignore` during installation and worktree creation, including when a launcher already exists.

## [0.1.6] - 2026-02-11

### Added

- `bin/setup` support: runs project-specific setup script when available during initialization
- `cd` hint after closing a worktree from within it
- Test suite with minitest covering init and close commands

### Fixed

- Database separation: `close` now uses `dropdb` directly instead of `bin/rails db:drop`, ensuring the correct worktree-specific databases are dropped
- Database names in `database.yml` are now replaced via simple string substitution instead of fragile ERB regex, fixing cases where the worktree operated on the main database
- Early `chdir` to main worktree during close to avoid "directory does not exist" errors

## [0.1.5] - 2026-02-11

### Added

- `--skip-seeds` flag to skip database seeding during worktree creation and initialization
- `node_modules` cleanup when closing a worktree
- Support for `bin/setup` during worktree initialization (used when available)

### Changed

- Database names are now passed via environment variables instead of relying on `.env` files
- Improved database prefix detection with fallback to app directory name
- Gemspec now references `RailsWorktree::VERSION` instead of hardcoded version string
- Updated help text with new options and examples

### Fixed

- Database creation and teardown now work reliably without `.env` file dependency
