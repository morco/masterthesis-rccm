#!/usr/bin/env bash

_mydir="$(readlink -f "$0" | xargs dirname)"

ctab_creator="${_mydir}/create_tables.sh"


cset_file="${1:?}"
cset_to_cfgs="${cset_file}_cfgmap"

shift

if ! [ -e "${cset_to_cfgs}" ]; then

  cset_dir="$(dirname "${cset_file}")"

  while read cset_line; do

    cset="$(echo "${cset_line}" | awk -F';' '{print $2}' | sed 's/^\s*//' | sed 's/\s*$//' )"
    cfg="$(find "${cset_dir}" -ipath "*/$(echo "$cset" | tr ' ' '_' )/configs")"

    if [ -z "${cfg}" ]; then
      echo "ERROR: no configs file found for cset [${cset}]" >&2
      exit 1
    fi

    cfgcnt="$(echo "${cfg}" | wc -l)"

    if [ "${cfgcnt}" -ne 1 ]; then
      echo "ERROR: expected to find exactly one configs file for [${cset}], but found '${cfgcnt}':" >&2
      echo "${cfg}" >&2
      exit 1
    fi

    cfg="$(cat "${cfg}" | head -n1)"

    echo "${cfg} ; ${cset_line}" >> "${cset_to_cfgs}"
    
  done <<<"$(cat "${cset_file}")"

fi

echo "Start building table ..."
cat "${cset_to_cfgs}" | "${ctab_creator}" "$@"

