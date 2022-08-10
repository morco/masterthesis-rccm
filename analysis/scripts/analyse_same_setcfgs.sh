#!/usr/bin/env bash

fn_cleanup() {
  # kill all subjobs when this is stopped
  pkill -P $$
}

trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"

rccm_perm_bin="${_mydir}/../rccm-permutation-finder/version-2/bin/AddNet_Permutator_v2"
analyse_script="${_mydir}/run_analysis.sh"


test_sets_dir="${_mydir}/tsets_same_cset"

resdir_base="${1:-${_mydir}/results}"
gendir_base="${resdir_base}/coeff_gen"
my_resdir_base="${resdir_base}/same_coef_configs"


while read tset; do
  source "${test_sets_dir}/${tset}"

  set_disabled=''

  if [ -n "${set_disabled}" ]; then
    echo
    echo "test set '${tset}' disabled, skip it"
    continue
  fi

  while read cs; do

    duration_start="$(date +%s)"

    cset_resfile="${gendir_base}/$(echo "$cs" | awk '{print $1}')"

    if ! [ -e "$cset_resfile" ]; then
      echo "ERROR: cset_resfile '${cset_resfile}' does not exist" >&2
      exit 1
    fi

    cset="$(echo "$cs" | cut -d ' ' -f 2- | sed 's/^\s*//')"

    maxshift="$(echo "$cset_resfile" | grep -o 'maxshift_[0-9]\+' | grep -o '[0-9]\+')"

    echo
    echo "find all configs for coeff set '${cset}' ..."

    ## get original addnet mutator args from resfile and append
    ## the settings to produce all configs matching a given coeff set
    ##orig_args="$(
    ##  cat "${cset_resfile}" | head -n20 | grep -i "called with:" \
    ##    | sed 's/^\s*called with:\s*//i' \
    ##    | sed 's/--set_metric\s\+[a-zA-Z_-]\+//g' \
    ##    | sed 's/--configure\s\+[a-zA-Z_-]\+//g'
    ##)"

    ## WARNING: this methodology of using the permutator with different params still implies redoing a full depth search of config space as there exist no intelligent backwards method from cset to matching configs!!
    ## res="$("$rccm_perm_bin" ${orig_args} --set_metric equal\
    ##    --configure ${cset} --set_metric list-best --configure all --chain
    ## )"

    ## rc="$?"

    ## echo
    ## echo "$res"
    ## echo

    ## if [ "${rc}" -ne 0 ]; then
    ##   echo "ERROR: rccm perm mutator call failed" >&2
    ##   exit "${rc}"
    ## fi

    ## # all returned configs should have given cset, make sure this is the case
    ## bad_res="$(echo "${res}" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' | grep -v "	${cset}\s*\$")"

    ##if [ -n "${bad_res}" ]; then
    ##  echo "ERROR: rccm perm mutator call created unexpected results where coeff set is not expected value '[${cset}]:'" >&2
    ##  echo "${bad_res}" >&2
    ##  exit 1
    ##fi

    res="$(cat "$cset_resfile" | grep "	${cset}\$" | head -n13)"

    echo
    echo "$res"
    echo

    if [ -z "$res" ]; then
      echo "ERROR: did not find any configs" >&2
      exit 1
    fi

    if [ "$(echo "$res" | wc -l)" -lt 8 ]; then
      echo "ERROR: expect at least 8 configs" >&2
      exit 1
    fi

    cset_normed="$(echo "$cset" | sed 's/\s/_/g')"
    first_done=''

    while read cfg; do

      echo "do config '${cfg}' ..."

      if [ -z "$cfg" ]; then
        echo "ERROR: config was empty" >&2
        exit 1
      fi

      if [ -z "${first_done}" ]; then
        c_struct="$(echo "$cfg" | awk -F '-' '{print $2}' | tr '[:upper:]' '[:lower:]')"

        my_resdir="${my_resdir_base}/${target}/${testcat}/${c_struct}/${cset_normed}"

	test -d "$my_resdir" || mkdir -p "$my_resdir"

        meta_resfile="${my_resdir}/analyse_meta"

        #echo "$res" > "${my_resdir}/permutator_result"

        rm -f "${my_resdir}/configs"

        first_done=true
      fi

      echo "$cfg" >> "${my_resdir}/configs"

      echo
      echo "run hw analysis for target '${target}' and config '${cfg}' ..."
      "${analyse_script}" "${target}" "${cfg}"

##      cat >> "${my_resdir_base}/${target}/${testcat}/tab_cfgmap" <<EOOF
##${cfg} ; ${meta_resfile} ; ${cset}
##EOOF

##    done <<<"$(
##      echo "${res}" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' | awk '{print $3}'
##    )"

    done <<<"$(
      echo "${res}" | awk '{print $3}'
    )"

    duration_end="$(date +%s)"

    cat > "${meta_resfile}" <<EOOF

duration=$(( duration_end - duration_start ))s

target=${target}
testcat=${testcat}
connect=${c_struct}
max_shift=${maxshift}
modules=${modules}

EOOF

  done <<<"$(echo "${csets}")"
done <<<"$(ls -1 "${test_sets_dir}")"

echo

