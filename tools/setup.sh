#!/usr/bin/env sh
# Installs what the Godot project (project/) needs and no repository carries:
# the godot-sqlite binaries, which BookletPackReader reads language.db with.
# Safe to re-run.
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

echo "== godot-sqlite binaries"
if [ -z "$(missing_libs "$bin")" ]; then
	echo "already installed"
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
		exit 0
	fi
done
echo "MISSING: no Kalulu-Frontend checkout with the binaries was found." >&2
echo "Install godot-sqlite 4.7 from https://github.com/2shady4u/godot-sqlite/releases" >&2
echo "into project/$bin_rel, or set KALULU_FRONTEND to a checkout that has them." >&2
echo "Missing:" >&2
missing_libs "$bin" | sed 's/^/  /' >&2
exit 1
