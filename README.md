# Rails Worktree

Provisions git worktrees for Rails projects: configuration files, node_modules and optional
isolated databases, in a checkout created by `bin/worktree`, plain git, herdr, Claude Code or Codex.

## Features

- `bin/worktree init` prepares any linked worktree at one of three levels, and is safe to repeat:
  - `minimal`: copies gitignored configuration from the main checkout, creates directories, links `node_modules`.
  - `test`: minimal plus your isolated test setup command, or an own test database.
  - `full`: minimal plus own development and test databases. The development database is cloned
    from the main one with `CREATE DATABASE ... TEMPLATE` (PostgreSQL), so it is ready in seconds.
- `bin/worktree create NAME BASE` creates a worktree under `.worktrees/` from an explicit base and provisions it.
- `bin/worktree install` writes the integration files other tools read: `.worktreeinclude` for Claude Code,
  a `## Worktrees` block in `AGENTS.md`/`CLAUDE.md` for coding agents, and a herdr plugin.
- `exec` and `verify` run commands with worktree-local Bundler and binstubs and check the recorded base.
- `close` drops the worktree-local databases, removes the checkout and deletes its branch.

## Installation

Add to your `Gemfile`:

```ruby
group :development do
  gem "rails-worktree"
end
```

Run `bundle install`. When Rails loads in development the gem installs `bin/worktree` and the
integration files below. The same happens with `bin/worktree install` or `bundle exec rake worktree:install`
(`--force` / `FORCE=1` also replaces an existing launcher).

| File | Purpose |
| --- | --- |
| `bin/worktree` | Launcher that pins `BUNDLE_GEMFILE` to its own checkout before Ruby starts |
| `.gitignore` | Adds `/.worktrees/` |
| `.worktree.yml` | Project configuration (written once with the defaults, then yours) |
| `.worktreeinclude` | Generated from the `copy` list; Claude Code copies these files into every worktree it creates |
| `AGENTS.md`, `CLAUDE.md` | A marked `## Worktrees` block that tells agents to run `bin/worktree init`; a symlinked pair is updated once |
| `.worktree/herdr/` | A herdr plugin that runs `bin/worktree init --level minimal` on `worktree.created`; link it once with `herdr plugin link .worktree/herdr` |

Commit `.worktree.yml`, `.worktreeinclude`, the agents block and `.worktree/herdr/`. They are project configuration.

## Configuration

`.worktree.yml` in the repository root, all keys optional:

```yaml
level: full                      # default level for create and init
copy:                            # gitignored files to copy from the main checkout (globs)
  - .env
  - .env.*
  - config/database.yml
  - config/master.key
  - config/credentials/*.key
  - Procfile.dev
directories: [tmp/pids]          # created in every provisioned checkout
touch: [tmp/caching-dev.txt]     # touched in every provisioned checkout
node_modules: link               # link (symlink to the main checkout), copy or skip
database:
  development_variable: DATABASE_NAME   # written to .env.development.local
  test_variable: DATABASE_NAME          # written to .env.test.local
  template: true                        # clone the main development database (PostgreSQL)
  template_max_gb: 5                    # larger source databases load the schema instead
test_command: bin/agent-test-setup      # --level test runs this instead of creating a test database
```

`config/database.yml` reads the database name from the configured variable, for example:

```yaml
development:
  <<: *default
  database: <%= ENV.fetch("DATABASE_NAME", "myapp_development") %>
test:
  <<: *default
  database: <%= ENV.fetch("DATABASE_NAME", "myapp_test") %>
```

Database names are `<prefix>_<worktree>_development` and `<prefix>_<worktree>_test`. The prefix comes from
`config/database.yml` in the main checkout, the worktree name from the directory, with other characters
replaced by `_`. The names go into `.env.development.local` and `.env.test.local`, which dotenv loads per
environment and which stay out of git. `database.yml` is copied unchanged.

## Usage

```bash
git fetch origin
bin/worktree create feature origin/main                 # full provisioning
bin/worktree create spike origin/main --level minimal   # shares the main development database
bin/worktree create feature origin/main --seed          # also run db:seed

# In a checkout another tool created (herdr, claude --worktree, Codex, git worktree add)
bin/worktree init                     # level from .worktree.yml
bin/worktree init --level test        # plus the isolated test setup
bin/worktree init --base origin/main  # also record the base and install the push guard
bin/worktree init --force             # overwrite copied files with the main checkout's

bin/worktree close feature            # from the main checkout
bin/worktree close                    # from inside the worktree
```

The base for `create` is required and the resolved commit is recorded; creation does not fetch or change
your base branch. If the template clone cannot run, because the main development database is in use or larger
than `template_max_gb`, `init` creates the database and loads the schema instead and says so.

`close` drops only databases named in the worktree's `.env.development.local` and `.env.test.local`.
A `minimal` checkout shares the main databases and they stay untouched.

## Verified execution

```bash
cd .worktrees/feature
bin/worktree exec -- bundle exec rspec
bin/worktree verify
```

`exec` runs from the worktree root with `BUNDLE_GEMFILE` pinned to this checkout, clears inherited Bundler
state and Git directory overrides, removes other repositories' `bin` directories from PATH and puts this
checkout's `bin` first. It rejects binstubs that resolve into another repository. It needs the metadata
that `create` or `init --base` records in the private `rails-worktree.json` under `git rev-parse --git-dir`;
checkouts without it skip the guard.

`create` and `init --base` also install a pre-push wrapper at Git's configured hook location. An existing
hook is preserved as `pre-push.before-rails-worktree` and runs after verification. In managed worktrees the
hook checks the branch, base ancestry and bundle root, then prints the change summary against the recorded
base. Git's `--no-verify` still bypasses hooks.

## Requirements

- Ruby >= 3.0
- Rails project with `bin/rails` and dotenv (for the per-environment `.env.*.local` files)
- PostgreSQL for template cloning; other databases fall back to `db:create` and `db:schema:load`

## License

MIT
