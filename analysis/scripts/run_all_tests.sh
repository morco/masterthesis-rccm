#!/usr/bin/env bash

fn_cleanup() {
  # kill all subjobs when this is stopped
  pkill -P $$
}

trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"

test_sets_dir="${_mydir}/test_sets"

while read tset; do
  set_disabled=''
  recfgmode=''
  source "${test_sets_dir}/${tset}"

  if [ -n "${set_disabled}" ]; then
    echo
    echo "test set '${tset}' disabled, skip it"
    continue
  fi

  if [ -n "${recfgmode}" ]; then
    # run in recfg mode
    while read c; do

      echo
      echo "run hw analysis for reconfigurable cfg '${c}' ..."

      ##echo "${_mydir}/run_analysis.sh" "${target}" "$c" true
      "${_mydir}/run_analysis.sh" "${target}" "$c" true

    done <<<"${cfgs}"

    continue
  fi

  echo
  echo "find coeff sets: '${testcat}' '${modules}' '${opmode}' ..."
  ##echo "${_mydir}/create_coef_sets" "${testcat}" "${modules}" "${opmode}"
  ##"${_mydir}/create_coef_sets.sh" "${testcat}" "${modules}" "${opmode}"

  echo
  echo "map all found coefficient sets ..."
  ##echo "${_mydir}/map_sets_to_cfgs"
  ##"${_mydir}/map_sets_to_cfgs.sh"

  echo
  echo "run hw analysis for all mapped configs ..."
  ##echo "${_mydir}/analyse_all_mapped_cfgs" "${target}"
  "${_mydir}/analyse_all_mapped_cfgs.sh" "${target}"

done <<<"$(ls -1 "${test_sets_dir}")"

echo

