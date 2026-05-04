# CLAUDE.md — mypinboard

A fork of [linkding](https://github.com/sissbruecker/linkding) adapted for deployment on [Once (Hetzner)](https://once.com/).

**Forked from:** linkding v1.45.0 (2026-01-06)  
**Live URL:** configured via Once TUI

---

## Our changes vs upstream

All our modifications are small and confined to specific locations. Knowing exactly what we changed is critical for safe merging.

| What | Where | Why |
|---|---|---|
| Added `/up` health route | `bookmarks/urls.py` line 112 | Once requires `GET /up → 200` |
| Changed default port 9090 → 80 | `bootstrap.sh` line 4 | Once serves on port 80 |
| Changed `EXPOSE` 9090 → 80 | `docker/alpine.Dockerfile` line ~75 | Once serves on port 80 |
| Changed healthcheck to use `/up` | `docker/alpine.Dockerfile` HEALTHCHECK | Matches our `/up` route |
| Added `docker-compose.once.yml` | repo root | Once deployment config (mounts `/storage`) |
| Added `.github/workflows/docker.yml` | `.github/workflows/` | CI: builds and pushes to `ghcr.io/tkrag/mypinboard:latest` |

---

## Running locally

```bash
make init              # uv sync, npm install, migrations, create data/
uv run manage.py createsuperuser
make serve             # Django dev server
make frontend          # Rollup watch (separate terminal)
make tasks             # Huey task queue (separate terminal)

make test              # pytest -n auto
make lint              # ruff check
make format            # ruff format + djlint + prettier
make e2e               # Playwright E2E
```

## Deploying

Push to `main` → GitHub Actions builds and pushes `ghcr.io/tkrag/mypinboard:latest` → in Once TUI, pull the latest image.

---

## Merging upstream linkding updates

Only merge upstream when there is a **security fix** or a feature you actually want. Cosmetic releases and minor patches are not worth the merge risk.

### Step 1 — Check what's new

Go to https://github.com/sissbruecker/linkding/releases. Compare the latest version against our fork base (**v1.45.0**). Read the changelog for:
- Security vulnerabilities → merge immediately
- Breaking changes → read carefully before merging
- New features → optional, merge if useful

### Step 2 — Add the upstream remote (one time only)

```bash
git remote add upstream https://github.com/sissbruecker/linkding.git
git fetch upstream
```

Confirm the remote exists with `git remote -v`.

### Step 3 — Create a merge branch

```bash
git checkout -b merge/linkding-vX.Y.Z
```

Never merge directly to `main`.

### Step 4 — Merge upstream

```bash
git fetch upstream
git merge upstream/main --no-ff -m "Merge linkding vX.Y.Z"
```

### Step 5 — Resolve conflicts

Conflicts are most likely in these files — here is how to resolve each:

**`bootstrap.sh`**
- Keep `LD_SERVER_PORT="${LD_SERVER_PORT:-80}"` (our change)
- Accept all other upstream changes

**`docker/alpine.Dockerfile`**
- Keep `EXPOSE 80`
- Keep the HEALTHCHECK using `${LD_SERVER_PORT:-80}` and `/up`
- Accept all other upstream changes

**`bookmarks/urls.py`**
- Keep `path("up", health_view, name="health.up"),` — do not remove this line
- Accept all other upstream routing changes

**`docker-compose.once.yml`** — upstream won't touch this; no conflict expected.

**`.github/workflows/docker.yml`** — upstream won't touch this; no conflict expected.

After resolving, mark files resolved:
```bash
git add bootstrap.sh docker/alpine.Dockerfile bookmarks/urls.py
git merge --continue
```

### Step 6 — Run migrations

Upstream may add new migrations. Apply them:
```bash
uv run manage.py migrate
```

Check for any new migration files — if the migration history has changed, make sure `uv.lock` / dependencies are up to date too.

### Step 7 — Verify the build

```bash
make test
docker build -f docker/alpine.Dockerfile -t mypinboard:test .
docker run --rm -p 8080:80 mypinboard:test
curl http://localhost:8080/up   # must return 200
curl http://localhost:8080/health
```

### Step 8 — Merge to main and deploy

```bash
git checkout main
git merge --no-ff merge/linkding-vX.Y.Z
git push origin main
```

GitHub Actions will build and push the new image. Wait for CI green, then in the Once TUI pull the latest image.

Update the forked-from version in this file: `**Forked from:** linkding vX.Y.Z`.

---

## What NOT to do

- Do not `git rebase` onto upstream — we have a small number of local commits and rebasing is fragile across large upstream histories
- Do not merge upstream minor releases just because they exist — only merge security fixes and wanted features
- Do not change the default port back to 9090 — Once requires port 80
- Do not remove the `/up` route — Once health-checks on that path
