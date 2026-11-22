#!/usr/bin/env sh
# Installs what the Godot project (project/) needs and no repository carries:
# the godot-sqlite binaries, which BookletPackReader reads language.db with;
# then imports the project, which writes the class list the scripts find each
# other by. Safe to re-run, and to be re-run after a pull: a new script is
# unknown to the command line until the next import.
#
# They are copied from a Kalulu-Frontend checkout that has them (~320 MB there,
# gitignored in every repository): $KALULU_FRONTEND, else a Kalulu-Frontend
# folder beside this repository (the Kalulu-Main layout). Only the six desktop
# libraries are copied: the generator runs on macOS, Windows and Linux.
#
# Without Kalulu-Frontend, install godot-sqlite 4.7 from
# https://github.com/2shady4u/godot-sqlite/releases into
# project/addons/godot-sqlite/bin/ (the Godot Tests workflow does that).

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
bin_rel="addons/godot-sqlite/bin"
bin="$root/project/$bin_rel"
libs="libgdsqlite.macos.template_debug.framework
libgdsqlite.macos.template_release.framework
libgdsqlite.windows.template_debug.x86_64.dll
libgdsqlite.windows.template_release.x86_64.dll
libgdsqlite.linux.template_debug.x86_64.so
libgdsqlite.linux.template_release.x86_64.so"

missing_libs() {
	# Prints the desktop libraries absent from the folder given.
	for lib in $libs; do
		[ -e "$1/$lib" ] || echo "$lib"
	done
}

import_project() {
	# $GODOT, else what Kalulu-Main's kalulu-env.sh finds when this repository
	# sits in it, else godot on the PATH.
	godot="${GODOT:-}"
	env_script="$root/../scripts/kalulu-env.sh"
	if [ -z "$godot" ] && [ -f "$env_script" ] && command -v bash >/dev/null 2>&1; then
		godot="$(bash -c '. "$1" >/dev/null 2>&1; printf %s "${GODOT:-}"' _ "$env_script")"
	fi
	[ -n "$godot" ] || godot="$(command -v godot 2>/dev/null || true)"
	echo "== import"
	if [ -z "$godot" ]; then
		echo "Godot not found: set GODOT, then run" >&2
		echo "  godot --headless --path project --import" >&2
		exit 1
	fi
	"$godot" --headless --path "$root/project" --import >/dev/null 2>&1 || true
	# The import's exit code says nothing: check the class list it writes.
	if grep -q '"BookletBuild"' "$root/project/.godot/global_script_class_cache.cfg" 2>/dev/null; then
		echo "done"
	else
		echo "the import did not write the class list: run it by hand to see why" >&2
		echo "  $godot --headless --path project --import" >&2
		exit 1
	fi
}

echo "== godot-sqlite binaries"
if [ -z "$(missing_libs "$bin")" ]; then
	echo "already installed"
	import_project
	exit 0
fi
for candidate in "${KALULU_FRONTEND:-}" "$root/../Kalulu-Frontend"; do
	[ -n "$candidate" ] || continue
	if [ -d "$candidate/$bin_rel" ] && [ -z "$(missing_libs "$candidate/$bin_rel")" ]; then
		mkdir -p "$bin"
		for lib in $libs; do
			rm -rf "$bin/$lib"
			# -P keeps symlinks as symlinks: the macOS frameworks need their
			# Versions/Current layout (Kalulu-Main's repair-godot-sqlite-framework.sh).
			cp -RP "$candidate/$bin_rel/$lib" "$bin/"
		done
		echo "copied from $candidate/$bin_rel"
		import_project
		exit 0
	fi
done
echo "MISSING: no Kalulu-Frontend checkout with the binaries was found." >&2
echo "Install godot-sqlite 4.7 from https://github.com/2shady4u/godot-sqlite/releases" >&2
echo "into project/$bin_rel, or set KALULU_FRONTEND to a checkout that has them." >&2
echo "Missing:" >&2
missing_libs "$bin" | sed 's/^/  /' >&2
exit 1
