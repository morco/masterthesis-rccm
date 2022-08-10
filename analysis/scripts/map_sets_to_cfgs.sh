#!/usr/bin/env bash

PARALLEL_RUNS=1

fn_cleanup() {
  # kill all subjobs when this is stopped
  pkill -P $$
}

trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"


fn_map_sets() {
  local cset="${1:?}"
  local myres_base="${2:?}"
  local raw_resfile="${3:?}"

  local cset_bucket="$(echo "$cset" | awk '{print $1}')"
  local cset_normed="$(echo "$cset" | sed 's/\s\+/_/g')"
  local cset_dir="${myres_base}/${cset_bucket}/${cset_normed}"
  local cset_dir_srclinks="${cset_dir}/generated_by"

  local cset_cfgs="${cset_dir}/configs"

  if [ -e "$cset_cfgs" ]; then
    ##rm -rf "$(dirname "${cset_cfgs}")"
    echo "cset already handled, skipping ..."
    return 0
  fi

  # note: prefix (this is a tab!) and suffix for key matching is important
  #   here to avoid matching partial coef sets
  ##local csdat="$(echo "$combined_res" | grep -- "	${cset}\s*\$")"

  test -d "${cset_dir_srclinks}" || mkdir -p "${cset_dir_srclinks}"

  ##unset meta_shifts
  ##unset meta_connect
  ##unset meta_modules
  ##unset meta_testcats

  ## note: it seems declare is automatically local inside a function, so great
  declare -A meta_shifts
  declare -A meta_connect
  declare -A meta_modules
  declare -A meta_testcats

  ##set -x
  declare -a sources
  local cs_src

  while read cs_src; do

    local srcdir="$(dirname "${cs_src}")"
    source "${srcdir}/analyse_meta"

    sources+=("$srcdir/permutator_result")

    ## link to current generate dir
    local tmp="$(realpath --relative-to="${cset_dir_srclinks}" "${srcdir}")"

    (
      cd "${cset_dir_srclinks}" || exit "$?"
      ln -s "$tmp" "${perm_id:?}" || exit "$?"
    ) || return "$?"

    ## collect metadata
    meta_shifts["${max_shift}"]=true
    meta_connect["${connect}"]=true
    meta_modules["${modules}"]=true
    meta_testcats["${testcat}"]=true

    ## save all configs for this coeff set
    grep -e "	${cset}\s*\$" "${srcdir}/permutator_result" | awk '{print $3}' >> "${cset_cfgs}"

  done <<<"$(grep -e "\s;\s${cset}\s*\$" "${raw_resfile}" | awk -F';' '{print $1}' | sed 's/^\s*//' | sed 's/\s*$//')"

  if [ -z "$(cat "${cset_cfgs}")" ]; then
    echo "ERROR: failed to find a single cfg for cset '${cset}' in any of these source files:" >&2
    echo "${sources[@]}" >&2
    rm -rf "${cset_dir}"

    return 1
  fi

  ## ## save all configs for this coeff set
  ## echo "$csdat" | awk '{print $5}' | sort | uniq > "${cset_cfgs}"
  mv "${cset_cfgs}" "${cset_cfgs}_tmp"
  cat "${cset_cfgs}_tmp" | sort -u >> "${cset_cfgs}"

  rm -f "${cset_cfgs}_tmp"

  if [ -z "$(cat "${cset_cfgs}")" ]; then
    echo "ERROR: uniq step cleared all configs somehow for '${cset}'" >&2
    rm -rf "${cset_dir}"

    return 1
  fi

  ## save all metadata for this set
  local cset_meta_dir="${cset_dir}/analyse_meta.d"
  test -d "${cset_meta_dir}" || mkdir -p "${cset_meta_dir}"

  for k in "${!meta_shifts[@]}"; do
    echo "$k" >> "${cset_meta_dir}/max_shift"
  done

  for k in "${!meta_connect[@]}"; do
    echo "$k" >> "${cset_meta_dir}/connect"
  done

  for k in "${!meta_modules[@]}"; do
    echo "$k" >> "${cset_meta_dir}/modules"
  done

  for k in "${!meta_testcats[@]}"; do
    echo "$k" >> "${cset_meta_dir}/testcats"
  done

  cat > "${cset_dir}/analyse_meta" <<EOOF
cset=$cset
EOOF
}


fn_permres_cmd() {
  if [ "$2" -gt 0 ]; then
    ##cat "$1" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' | sed "s,^,$1  ," | shuf -n "$2"
    cat "$1" | sed "s,^,$1 ; ," | shuf -n "$2"
  else
    ##cat "$1" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' | sed "s,^,$1  ,"
    cat "$1" | sed "s,^,$1 ; ,"
  fi
}


##
## note: the amount of potential sets to generate is absolute gigantic,
##   but we only have limited time of resources, so the final number
##   of configs to analyse should be around 500 max or maybe 1000 max
##
max_sets_per_file="${1:-5}"
resdir_base="${2:-${_mydir}/results}"

src_pathfilter="${3}"
rawres_file="${4}"

gendir_base="${resdir_base}/coeff_gen"
myres_base="${5:-${resdir_base}/coeff_sets}"
allmeta="${myres_base}/analyse_meta"

test -d "${myres_base}" || mkdir -p "${myres_base}"

# TODO: how well does this scale, better to use a tmpfile here??
export "max_sets_per_file=${max_sets_per_file}"
export -f fn_permres_cmd

if [ -z "${rawres_file}" ]; then
  rawres_file="${myres_base}/combined_sets"
  
  if [ "${max_sets_per_file}" -gt 0 ]; then
    rawres_file="${rawres_file}_max${max_sets_per_file}"
  else
    rawres_file="${rawres_file}_all"
  fi
fi

if ! [ -e "${rawres_file}" ]; then
  find_extrargs=()
  
  if [ -n "${src_pathfilter}" ]; then
    find_extrargs+=("-ipath" "$src_pathfilter")
  fi
  
  # save combined sets file for further analysis
  find "${gendir_base}" -iname "sorted_unique_keys_only_maxshift" \
    ${find_extrargs[@]} \
    -exec bash -c 'fn_permres_cmd "$0" "${max_sets_per_file}"' {} ";" > "${rawres_file}"

fi

duration_sumtime_start="$(date +%s)"
cset_cnt=0
pids=()

while read cset; do
  cset_cnt=$((cset_cnt+1))
  ##echo "cset: |$cset|"

  ##
  ## note: as we have all the different perm data before hand as one
  ##   big chunk in this implementation we can easily run the mapping
  ##   in parallel, as they dont interfere with each other
  ##
  ## n.2: running in subshell seems safer here to guarantee unique variables
  ##
  (
    fn_map_sets "${cset}" "${myres_base}" "${rawres_file}" || exit "$?"
  ) &

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

done <<<"$(cat "${rawres_file}" | awk -F';' '{print $2}' | sed 's/^\s*//' | sed 's/\s*$//' | sort -u)"

## finally dont forget to wait for the final batch to finish
for p in "${pids[@]}"; do
  wait "$p" || exit "$?"
done

duration_sumtime_end="$(date +%s)"
duration_sum=$(( duration_sumtime_end - duration_sumtime_start ))

cat > "${allmeta}" <<EOOF
coef_sets: ${cset_cnt}
duration: ${duration_sum}s
time_per_set: $(bc <<<"scale=4; $duration_sum / $cset_cnt")s
EOOF

## note: below is first implementation for above which also works, but has two big disadvantadges:
##  A) seems slower in general
##  B) is not "thread safe" / not easily to work with in parallel, which also means slower
## ## for each permutator result file
## while read pres_file; do
## 
##   pres_dir="$(dirname "$pres_file")"
##   tabdata="$(cat "${pres_file}" | awk '/----------/{flag=1;next}/---------/{flag=0}flag')"
## 
##   source "${pres_dir}/analyse_meta"
## 
##   ## for each coeff set in perm res
##   while read cset; do
## 
##     cset_normed="$(echo "$cset" | sed 's/\s\+/_/g')"
##     cset_dir="${myres_base}/${cset_normed}"
##     cset_dir_srclinks="${cset_dir}/generated_by"
## 
##     ## link to current generate dir
##     test -d "${cset_dir_srclinks}" || mkdir -p "${cset_dir_srclinks}"
## 
##     tmp="$(realpath --relative-to="${cset_dir_srclinks}" "${pres_dir}")"
## 
##     (
##       cd "${cset_dir_srclinks}" || exit "$?"
##       ln -s "$tmp" "${perm_id:?}" || exit "$?"
##     ) || exit "$?"
## 
##     ## get current pres config for this set and add it to list of configs for this set
##     cset_cfgs="${cset_dir}/configs"
## 
##     echo "$tabdata" | grep -- "${cset}" | awk '{print $4}' >> "${cset_cfgs}"
## 
##     ## assure that configs list has no duplicates
##     cat "${cset_cfgs}" | sort | uniq  > "${cset_cfgs}_tmp"
##     mv "${cset_cfgs}_tmp" "${cset_cfgs}"
## 
##     ## collect meta data for each set
##     cset_meta_dir="${cset_dir}/analyse_meta.d"
##     test -d "${cset_meta_dir}" || mkdir -p "${cset_meta_dir}"
## 
##     echo "${max_shift:?}" >> "${cset_meta_dir}/max_shift"
##     cat "${cset_meta_dir}/max_shift" | sort | uniq  > "${cset_meta_dir}/max_shift_tmp"
##     mv "${cset_meta_dir}/max_shift_tmp" "${cset_meta_dir}/max_shift"
## 
##     echo "${connect:?}" >> "${cset_meta_dir}/connect"
##     cat "${cset_meta_dir}/connect" | sort | uniq  > "${cset_meta_dir}/connect_tmp"
##     mv "${cset_meta_dir}/connect_tmp" "${cset_meta_dir}/connect"
## 
##     echo "${modules:?}" >> "${cset_meta_dir}/modules"
##     cat "${cset_meta_dir}/modules" | sort | uniq  > "${cset_meta_dir}/modules_tmp"
##     mv "${cset_meta_dir}/modules_tmp" "${cset_meta_dir}/modules"
## 
##     echo "${testcat:?}" >> "${cset_meta_dir}/testcats"
##     cat "${cset_meta_dir}/testcats" | sort | uniq  > "${cset_meta_dir}/testcats_tmp"
##     mv "${cset_meta_dir}/testcats_tmp" "${cset_meta_dir}/testcats"
## 
##   done <<<"$(echo "$tabdata" | cut  -f 5-)"
## done <<<"$(find "${gendir_base}" -iname "permutator_result")"

