#!/usr/bin/env bash

## fn_cleanup() {
##   # kill all subjobs when this is stopped
##   pkill -P $$
## }
## 
## trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"

rccm_perm_bin="${_mydir}/../rccm-permutation-finder/version-2/bin/AddNet_Permutator_v2"


testtype="${1:?}"
src_setfile="${2:?}"

##resdir_base="${3:-${_mydir}/results}"
##my_resdir_base="${resdir_base}/same_coef_configs"


while read cset; do

  while read cs_src; do

    srcdir="$(dirname "${cs_src}")"

    echo
    echo -n "test coeff set [${cset}] and source dir '${srcdir}' ..."

    ## get original addnet mutator args from resfile and append
    ## the settings to produce all configs matching a given coeff set
    orig_args="$(
      cat "${srcdir}/permutator_result" | head -n20 | grep -i "called with:" \
        | sed 's/^\s*called with:\s*//i' \
        | sed 's/--set_metric\s\+[a-zA-Z_-]\+//g' \
        | sed 's/--configure\s\+[a-zA-Z_-]\+//g' \
        | sed 's/--set_sel_add\s\+[a-zA-Z_-]\+//g' \
        | sed 's/--set_operation_mode\s\+[a-zA-Z_-]\+//g'
    )"

    res="$("$rccm_perm_bin" ${orig_args} --set_sel_add ${testtype} \
       --set_operation_mode all \
       --set_metric equal --configure ${cset} \
       --set_metric list-best --configure all --chain
    )"

    rc="$?"

    ##echo
    ##echo "$res" | head
    ##echo

    if [ "${rc}" -ne 0 ]; then
      echo
      echo "$res"
      echo

      echo "ERROR: rccm perm mutator call failed" >&2
      exit "${rc}"
    fi

    ##
    ## note: atm the permutator does not return with an rc != 0 or
    ##   even an empty result list when given coeff set is not part
    ##   of a type, not exactly sure what exactly is happening, but
    ##   in principle a list of various configs is returned, with
    ##   the difference being that none matches the given coeff set
    ##
    bad_matches="$(echo "$res" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' | grep -v "	${cset}\s*\$")"

    if [ -n "$bad_matches" ]; then

      echo "  failed!"
      echo "${bad_matches}" | head -n20
      echo "[...]"
      echo

      exit 1
    fi

    echo "  ok!"

  done <<<"$(grep -e "\s;\s${cset}\s*\$" "${src_setfile}" | awk -F';' '{print $1}' | sed 's/^\s*//' | sed 's/\s*$//' )"
done <<<"$(cat "${src_setfile}" | awk -F';' '{print $2}' | sed 's/^\s*//' | sed 's/\s*$//' | sort -u )"


echo
echo "Test succesful, all tested sets are constructable by testtype '${testtype}'"
echo

