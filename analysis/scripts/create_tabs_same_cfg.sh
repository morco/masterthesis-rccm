#!/usr/bin/env bash

_mydir="$(readlink -f "$0" | xargs dirname)"


ctab_creator="${_mydir}/create_tables.sh"


cfgmap_file="${1}"
resfile="${2:-${_mydir}/results/tables/same_cfg.csv}"


if [ -z "$cfgmap_file" ]; then

  while read tsetfile; do

    source "${_mydir}/tsets_same_cset/$tsetfile"

    cfgmap_file="${_mydir}/results/same_coef_configs/${testcat}_${target}_cfgmap"

    while read csetline; do
      presfile="$(echo "${csetline}" | awk '{print $1}')"
      cset="$(echo "${csetline}" | sed 's,^[^ ]\+\s\+,,')"

      cs_normed="$(echo "$cset" | sed 's/\s/_/g' )"

      cfgs="$(find "${_mydir}/results/same_coef_configs/" \
        -ipath "*/${target}/*/${cs_normed}/configs")"

      if [ -z "$cfgs" ]; then
        echo "ERROR: did not match any config" >&2
        exit 1
      fi

      ccnt="$(echo "$cfgs" | wc -l)"

      if [ "$ccnt" -ne 1 ]; then
        echo "ERROR: must matched exactly one configs file ($ccnt):" >&2
        echo "$cfgs" >&2
        exit 1
      fi

      cfgs="$(find "${_mydir}/results/same_coef_configs/" \
        -ipath "*/${target}/*/${cs_normed}/configs" -exec cat "{}" ";")"

      ccnt="$(echo "$cfgs" | wc -l)"

      if [ "$ccnt" -le 5 ]; then
        echo "ERROR: to few cfgs found ($ccnt):" >&2
        echo "$cfgs" >&2
        exit 1
      fi

      while read c; do
        echo "${c} ; ${_mydir}/results/coeff_gen/${presfile} ; ${cset}" >> "$cfgmap_file"
      done <<<"$cfgs"

    done <<<"$csets"

    echo "Start building table for '$testcat' and '$target' ..."
    cat "${cfgmap_file}" | "${ctab_creator}" "$resfile" "$target"

  done <<<"$(ls -1 "${_mydir}/tsets_same_cset/")"

else

  echo "Start building table ..."
  cat "${cfgmap_file}" | "${ctab_creator}" "$@"

fi

