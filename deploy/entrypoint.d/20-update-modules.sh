#!/bin/sh
# Brings the marketplace modules to the list the image carries: installs and
# enables a module the list names that is not on disk, and updates them all
# after a core upgrade and whenever the list changes. The upstream entrypoint
# only migrates the core and the module code already on disk; a module written
# for the previous core keeps calling what the new core removed (three modules
# broke the dashboard at 1.19, 2026-10-21). deploy/pre-start.sh leaves the
# marker when the version changed; by the time this runs the core is migrated,
# which is the order the marketplace needs, since it serves releases per core
# version. The list is deploy/modules.txt with the versions
# tools/test-modules.sh passed with, copied into the image by
# deploy/Dockerfile.humhub; the copy applied last sits beside the
# configuration. A line "-id" in the list removes that module, files and
# tables; a module merely dropped from the list stays on disk. A marketplace that cannot be
# reached leaves marker and list for the next start and does not stop the site.
CONFIG=/var/www/localhost/htdocs/protected/config
MARKER=$CONFIG/.modules-need-update
TESTED=/usr/local/share/humhub-modules.txt
APPLIED=$CONFIG/.modules-applied
if [ ! -f "$MARKER" ] && cmp -s "$TESTED" "$APPLIED"; then
  exit 0
fi
cd /var/www/localhost/htdocs/protected
ok=true
for m in $(sed -nE 's/^-([a-z0-9_-]+).*/\1/p' "$TESTED"); do
  [ -d "modules/$m" ] || continue
  php yii module/remove "$m" || ok=false
done
for m in $(grep -vE '^[[:space:]]*(#|-|$)' "$TESTED" | cut -d' ' -f1); do
  [ -d "modules/$m" ] && continue
  php yii module/install "$m" && php yii module/enable "$m" || ok=false
done
if $ok && php yii module/update-all && php yii cache/flush-all; then
  rm -f "$MARKER"
  cp "$TESTED" "$APPLIED"
else
  echo "20-update-modules: the module update did not complete; it runs again at the next start" >&2
fi
exit 0
