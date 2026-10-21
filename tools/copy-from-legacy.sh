#!/bin/sh
# One-off: copy the site that runs today into production's canonical data
# directory, mapping the old layout onto the new one. Run on the NAS as root:
#
#   sudo tools/copy-from-legacy.sh              # files, while the old site runs
#   sudo tools/copy-from-legacy.sh --database   # also the database directory,
#                                               # after stopping its container
#
# Re-runnable: rsync --delete makes the copy match the source each time, so
# the final run in the service window carries everything written since.
# Nothing is started here.
set -eu

OLD=/volume1/docker/spejdernet_sondermark_dk/humhub
OLD_DB=/volume1/docker/spejdernet_sondermark_dk/db/data
OLD_DB_CONTAINER=spejdernet_sondermark_dk-db-1
NEW=$(grep -E '^DATA_DIR=' /volume1/docker/spejdernet.sondermark.dk/production/production.env | cut -d= -f2- | tr -d '"')
[ -n "$NEW" ] || { echo "DATA_DIR missing in production.env" >&2; exit 1; }
case "$NEW" in /volume1/docker/spejdernet.sondermark.dk/production/data) ;; *) echo "refusing: DATA_DIR is not the canonical path ($NEW)" >&2; exit 1;; esac

# DSM keeps thumbnail folders (@eaDir) beside indexed photos; they are not
# site data and are several times its size, so every copy leaves them out.
mkdir -p "$NEW/humhub" "$NEW/db"
echo "files: $OLD -> $NEW/humhub"
rsync -a --delete --exclude=@eaDir --exclude="#recycle" "$OLD/uploads/"      "$NEW/humhub/uploads/"
rsync -a --delete --exclude=@eaDir --exclude="#recycle" "$OLD/modules/"  "$NEW/humhub/modules/"
rsync -a --delete --exclude=@eaDir --exclude="#recycle" "$OLD/themes/"   "$NEW/humhub/themes/"
rsync -a --delete --exclude=@eaDir --exclude="#recycle" "$OLD/config/"   "$NEW/humhub/config/"
rsync -a --delete --exclude=@eaDir --exclude="#recycle" "$OLD/php-pages/" "$NEW/humhub/php-pages/"
mkdir -p "$NEW/humhub/assets" "$NEW/humhub/php-pages"

if [ "${1:-}" = "--database" ]; then
  if /usr/local/bin/docker ps --format '{{.Names}}' | grep -qx "$OLD_DB_CONTAINER"; then
    echo "stop $OLD_DB_CONTAINER first; a running database cannot be copied consistently" >&2; exit 1
  fi
  echo "database: $OLD_DB -> $NEW/db/data"
  mkdir -p "$NEW/db/data"
  rsync -a --delete --exclude=@eaDir --exclude="#recycle" "$OLD_DB/" "$NEW/db/data/"
fi
du -sh "$NEW"
