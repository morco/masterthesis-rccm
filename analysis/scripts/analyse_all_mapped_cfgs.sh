#!/usr/bin/env bash

##PARALLEL_RUNS=6
##
##fn_cleanup() {
##  # kill all subjobs when this is stopped
##  pkill -P $$
##}
##
##trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"

run_analysis="${_mydir}/run_analysis.sh"


target="${1:?}"
##target="${1:-virtex7}"
resdir_base="${2:-${_mydir}/results}"

mapdir_base="${resdir_base}/coeff_sets"

if [ "${target}" == "versal" ]; then
  mapdir_base="${resdir_base}/coeff_sets_versal"
fi

cfgcnt=0
while read cfgstr; do
  cfgcnt=$((cfgcnt+1))

  echo
  echo "do hw analysis for target '${target}' and config '${cfgstr}'"
  "${run_analysis}" "${target}" "${cfgstr}"

  echo

  ##if [ "${cfgcnt}" -ge "3" ]; then
  ##  break
  ##fi

##
## note: we will only test one config per coeffset here, and we arbitrary decided that we simply use the first one (there is a different test setting for explicitly testing difference between configs for the same coeff set)
##
done <<<"$(find "${mapdir_base}" -iname "configs" -exec head -n1 {} ";" | sort -u)"

