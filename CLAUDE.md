# CLAUDE.md — mypinboard

A fork of [linkding](https://github.com/sissbruecker/linkding) adapted for deployment on [Once (Hetzner)](https://once.com/).

**Based on:** linkding v1.47.0 (2026-09-13)  
**Live URL:** configured via Once TUI

---

## Our changes vs upstream

All our modifications are small and confined to specific locations. Knowing exactly what we changed is critical for safe upgrades.

| What | Where | Why |
|---|---|---|
| Added `/up` health route | `bookmarks/urls.py` (next to `health`) | Once requires `GET /up → 200` |
| Changed default port 9090 → 80 | `bootstrap.sh` line 5 | Once serves on port 80 |
| Link `data/` to `/storage` when it exists | `bootstrap.sh` (top) | Once only persists `/storage`; without this all data lives in the container and is lost on every update |
| `chown` of `data/` uses a trailing slash | `bootstrap.sh` | So it follows the `/storage` symlink |
| Changed `EXPOSE` 9090 → 80 | `docker/alpine.Dockerfile` | Once serves on port 80 |
| Changed healthcheck to use `/up` | `docker/alpine.Dockerfile` HEALTHCHECK | Matches our `/up` route |
| Added `docker-compose.once.yml` | repo root | For running with plain Docker Compose. **Once ignores this file.** |
| Added `.github/workflows/docker.yml` | `.github/workflows/` | CI: builds and pushes to `ghcr.io/tkrag/mypinboard:latest` |
| Added `CLAUDE.md` | repo root | This file |

To see the exact diff at any time: `git diff v1.47.0 HEAD` (after `git fetch upstream --tags`).

---

## Running locally

```bash
make init              # uv sync, npm install, migrations, create data/
uv run manage.py createsuperuser
make serve             # Django dev server
make frontend          # frontend watch (separate terminal)
make tasks             # Huey task queue (separate terminal)

make test              # pytest -n auto
make lint              # ruff check
make format            # ruff format + djlint + prettier
make e2e               # Playwright E2E
```

## Deploying

Push to `main` → GitHub Actions builds and pushes `ghcr.io/tkrag/mypinboard:latest` → in Once TUI, pull the latest image.

---

## Updating to a newer linkding release

Only update when there is a **security fix** or a feature you actually want.

**Important:** this repo does **not** share git history with upstream (the original fork was a squashed snapshot), so `git merge upstream/...` does not work. Instead, we take the new upstream tag's file tree as-is and re-apply our small set of changes on top. Upstream's default branch is `master`.

### Step 1 — Check what's new

Read https://github.com/sissbruecker/linkding/releases since our base version (see top of file). Look for security fixes and breaking changes. Check whether any new files appear in `bookmarks/migrations/` — those run automatically on container start.

### Step 2 — Fetch upstream

```bash
git remote add upstream https://github.com/sissbruecker/linkding.git   # one time only
git fetch upstream --tags
```

### Step 3 — Build the update branch

Replace `vOLD` with the base version at the top of this file and `vNEW` with the target tag.

```bash
git diff vOLD HEAD -- bookmarks/urls.py bootstrap.sh docker/alpine.Dockerfile > /tmp/once.patch
git checkout -b update/linkding-vNEW
git read-tree -u --reset vNEW          # working tree becomes exactly upstream vNEW
git checkout main -- docker-compose.once.yml .github/workflows/docker.yml CLAUDE.md
git apply --3way /tmp/once.patch       # re-apply our port/healthcheck/route edits
git diff --cached --stat vNEW          # must list only the files in the table above
```

If `git apply --3way` reports conflicts, resolve them keeping: `LD_SERVER_PORT` default `80` and the `/storage` link block in `bootstrap.sh`; `EXPOSE 80` and the `/up` HEALTHCHECK in the Dockerfile; the `path("up", ...)` line in `bookmarks/urls.py`.

Note: Nextcloud sync can strip executable bits from the working copy. Before committing, check `git ls-files -s bootstrap.sh` shows `100755`.

### Step 4 — Verify

```bash
uv sync && npm install
make test
uv run manage.py makemigrations --check --dry-run   # must say "No changes detected"
```

If Docker is available:
```bash
docker build -f docker/alpine.Dockerfile -t mypinboard:test .
docker run --rm -p 8080:80 mypinboard:test
curl http://localhost:8080/up   # must return 200
```

### Step 5 — Back up, merge to main and deploy

1. **Back up `/storage` on the server first** (it holds the SQLite DB, assets and favicons). Database migrations are one-way; the backup is the rollback path.
2. Merge and push:
   ```bash
   git checkout main
   git merge --ff-only update/linkding-vNEW
   git push origin main
   ```
3. Wait for CI green, then pull the latest image in the Once TUI. Check `/up` and that bookmarks are present.
4. Update the **Based on** version at the top of this file.

---

## What NOT to do

- Do not try to `git merge` or `git rebase` onto upstream — there is no shared history
- Do not update just because a release exists — only for security fixes and wanted features
- Do not change the default port back to 9090 — Once requires port 80
- Do not remove the `/up` route — Once health-checks on that path
- Do not remove the `/storage` link in `bootstrap.sh` — Once persists and backs up only `/storage`; anything else is wiped when the container is replaced
