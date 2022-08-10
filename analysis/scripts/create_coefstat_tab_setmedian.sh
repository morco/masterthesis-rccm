#!/usr/bin/env bash

_mydir="$(readlink -f "$0" | xargs dirname)"


testcat="${1:?}"
mods="${2:?}"
cstruct="${3:?}"
srcfile="${4:?}"
resfile="${5:?}"


resdir="$(dirname "${resfile}")"

test -d "${resdir}" || mkdir -p "${resdir}"

if ! [ -e "${resfile}" ]; then
  cat > "${resfile}" <<'EOOF'
testcat, modules, cstruct, coeffset, median
EOOF
fi

cat "$srcfile" | sed 's/\[//' | sed 's/\]:/,/' \
  | sed "s/^/${testcat}, ${mods}, ${cstruct}, /" >> "$resfile"

