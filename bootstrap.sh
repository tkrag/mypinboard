#!/usr/bin/env bash
# Bootstrap script that gets executed in new Docker containers

LD_SERVER_HOST="${LD_SERVER_HOST:-[::]}"
LD_SERVER_PORT="${LD_SERVER_PORT:-80}"

# Once only persists /storage, so keep the data folder there (Once deployment compatibility)
# The image's data folder is not empty (the build creates tasks.sqlite3), so only a database
# is worth keeping: move it to /storage if that has none, otherwise set it aside in /storage
if [ -d /storage ] && [ ! -L data ]; then
  if [ -e data/db.sqlite3 ] && [ ! -e /storage/db.sqlite3 ]; then
    echo "Moving existing data/ into /storage" >&2
    cp -a data/. /storage/ || exit 1
  elif [ -e data/db.sqlite3 ]; then
    unlinked="/storage/unlinked-data-$(date +%Y%m%d%H%M%S)"
    echo "WARNING: data/ and /storage both have a database, keeping /storage and moving data/ to $unlinked" >&2
    mkdir -p "$unlinked" && cp -a data/. "$unlinked/" || exit 1
  fi
  rm -rf data && ln -s /storage data
fi

# Create data folder if it does not exist
mkdir -p data
# Create favicon folder if it does not exist
mkdir -p data/favicons
# Create previews folder if it does not exist
mkdir -p data/previews
# Create assets folder if it does not exist
mkdir -p data/assets

# Generate secret key file if it does not exist
python manage.py generate_secret_key
# Run database migration
python manage.py migrate
# Enable WAL journal mode for SQLite databases
python manage.py enable_wal
# Create initial superuser if defined in options / environment variables
python manage.py create_initial_superuser
# Migrate legacy background tasks to Huey
python manage.py migrate_tasks

# Ensure folders are owned by the right user
chown -R www-data: /etc/linkding/data/

# Start processes
# Experimental: use supervisor to manage all processes, enables logging background tasks to stdout/stderr
if [ "$LD_SUPERVISOR_MANAGED" = "True" ]; then
  exec supervisord -c supervisord-all.conf
# Default: start background task processor as daemon, then uwsgi as main process
else
  if [ "$LD_DISABLE_BACKGROUND_TASKS" != "True" ]; then
    supervisord -c supervisord-tasks.conf
  fi
  exec uwsgi --http $LD_SERVER_HOST:$LD_SERVER_PORT uwsgi.ini
fi
