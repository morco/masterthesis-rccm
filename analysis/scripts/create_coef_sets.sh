#!/usr/bin/env bash

#
# from a given input config runs flopoco, auto generate a minimal wrapper code around generated for registers, run vivado scripts with the result
#

##
## with bigger shifts and bigger connects the possible number of sets here get humongus
##
##MAXLINES=12000
MAXLINES=150000010
PARALLEL_RUNS=6

_mydir="$(readlink -f "$0" | xargs dirname)"

##rccm_perm_bin="${_mydir}/../rccm-permutation-finder/version-2/bin/AddNet_Permutator_v2"
rccm_perm_bin="${_mydir}/../rccm-permfinder-fork/version-2/bin/AddNet_Permutator_v2"
analyse_script="${_mydir}/run_analysis.sh"


fn_cleanup() {
  # kill all subjobs when this is stopped
  pkill -P $$
}

trap fn_cleanup EXIT


_fn_create_sets() {
  local testcat="${1:?}"
  local modules="${2:?}"
  local opmode="${3:?}"
  local resdir_base="${4:?}"
  local cs="${5:?}"
  local max_shift="${6:?}"

  local duration_start="$(date +%s)"

  local cs_normed="$(echo "$cs" | tr ',' '_' | tr '[:upper:]' '[:lower:]')"
  local resdir="${resdir_base}/maxshift_${max_shift}/${cs_normed}"

  local analyse_meta="${resdir}/analyse_meta"
  local permres="${resdir}/permutator_result"
  local keyfile="${resdir}/sorted_unique_keys"

  if [ -e "${permres}" ]; then
    echo "RCCM permutator result exists already, skip generation ..."
    return 0
  fi

  ## run rccm permutator to generate all possible sets
  test -d "${resdir}" || mkdir -p "${resdir}"

  ##--set_metric count_sets
  ##--set_metric list-best --configure all

  echo -n "Calling rccm permutator with args: "
  cat <<EOOF
  --set_max_shift "$max_shift"\
  --set_rccm "$cs" --set_sel_add "$modules"\
  --set_operation_mode "$opmode"\
  --set_metric list-stream
EOOF

##  "$rccm_perm_bin" --set_max_shift "$max_shift" \
##     --set_rccm "$cs"  --set_sel_add "$modules" \
##     --set_operation_mode "$opmode" \
##     --set_metric count_sets | head -n "${MAXLINES}" > "${permres}"

  # update: replace extremely slow / long running metric with "dummy" metric which puts any found config out as is without doing any internal tests on them, this is extremely more faster
  ## "$rccm_perm_bin" --set_max_shift "$max_shift" \
  ##    --set_rccm "$cs"  --set_sel_add "$modules" \
  ##    --set_operation_mode "$opmode" \
  ##    --set_metric list-best --configure all | head -n "${MAXLINES}" > "${permres}"

  # update.2: replaced updated variant with new streaming variant to avoid memory issues completly
  "$rccm_perm_bin" --set_max_shift "$max_shift" \
     --set_rccm "$cs"  --set_sel_add "$modules" \
     --set_operation_mode "$opmode" \
     --set_metric list-stream > "${permres}"

  ##   --set_metric list-stream | head -n "${MAXLINES}" > "${permres}"

  rc="$?"

  if [ "${rc}" -ne 0 ]; then
    echo "ERROR: rccm perm mutator call failed" >&2
    return "${rc}"
  fi

  cat "${permres}" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' \
    | cut -f 4- | sort -u > "${keyfile}"

  cat "${permres}" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' \
    | grep -- "\(-[0-9]*${max_shift}[0-9]*-[0-9]\+-\?\)\|\(-[0-9]\+-[0-9]*${max_shift}[0-9]*-\?\)" \
    | cut -f 4- | sort -u > "${keyfile}_with_maxshift"

  local resdir_prev="${resdir_base}/maxshift_$((max_shift - 1))/${cs_normed}"

  # returns only the lines unique to first given file, so only "new" keys
  if [ -d "${resdir_prev}" ]; then
    comm -23 "${keyfile}_with_maxshift" "${resdir_prev}/$(basename "${keyfile}")" > "${keyfile}_only_maxshift"
  else
    (
      cd "${resdir}"
      ln -s "$(basename "${keyfile}")" "${keyfile}_only_maxshift"
    )
  fi

  local duration_end="$(date +%s)"
  local complete=''

  test "$(cat "$permres" | wc -l)" -ge "${MAXLINES}" || complete=true

  if [ -n "${complete}" ]; then
    #
    # for complete result files create a "is_complete"
    # symlink, this is useful for later analysis
    #
    (
      cd "${resdir}"
      ln -s sorted_unique_keys keys_complete
    )
  fi

  cat > "${analyse_meta}" <<EOOF
perm_id=${testcat}_ms${max_shift}_${cs_normed}

max_shift=${max_shift}
connect=${cs}
modules=${modules}
testcat=${testcat}

complete=${complete}

duration=$(( duration_end - duration_start ))s
EOOF

  echo ""
  cat "${analyse_meta}"
}


fn_create_sets() {
  for ms in "${max_shift[@]}"; do
    _fn_create_sets "$@" "$ms" || return "$?"
  done
}


testcat="${1:?}"
modules="${2:?}"
opmode="${3:?}"

##testcat="a_and_b"
##modules="A,B"
##opmode="all"

resdir_base="${_mydir}/results/coeff_gen/${testcat}"

duration_sumtime_start="$(date +%s)"

allmeta="${resdir_base}/analyse_meta"

##
## note: resfile C3 with ms=4 is a couple of gig's, which is a lot but should be temporarly acceptable
##
## note.2: any shift >4 kills the permutator with a bad alloc, the strong guess here is that it fills up the gigantic memory space of +500 gig completly
##
##declare -a max_shift=(2 3 4 5 6)
declare -a max_shift=(4)
##declare -a cstructs=("C1" "C2" "C3" "C4")
##declare -a cstructs=("C1" "C2" "C3")
##declare -a cstructs=("C1" "C2")
declare -a cstructs=("C2")

pids=()

for cs in "${cstructs[@]}"; do

  fn_create_sets "$testcat" "$modules" "$opmode" "$resdir_base" "$cs" &
  pids+=($!)

  ##
  ## run simu analysis in parallel for a given max
  ## number of parralel processes allowed
  ##
  while [ "${#pids[@]}" -ge "${PARALLEL_RUNS}" ]; do
    ## if all our avaible parallel slots are full,
    ## wait until one is avaible again
    wait -n "${pids[@]}" || exit "$?"

    # important: dont forget to update current subprocess
    #   pids array and remove the ones which finished
    pids=($(jobs -rl | awk '{print $2}' | tr '\n' ' '))
  done

done

## finally dont forget to wait for the final batch to finish
for p in "${pids[@]}"; do
  wait "$p" || exit "$?"
done

duration_sumtime_end="$(date +%s)"

cat > "${allmeta}" <<EOOF
duration: $(( duration_sumtime_end - duration_sumtime_start ))s
EOOF

