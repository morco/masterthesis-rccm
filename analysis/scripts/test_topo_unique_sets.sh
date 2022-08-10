#!/usr/bin/env bash

origdir="$(pwd)"

fn_cleanup() {
  # kill all subjobs when this is stopped
  ##pkill -P $$

  cd "${origdir}"
}

trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"


##
## test if all keys of first coeff_gen substructure are part of 2nd param substructure
##
testid="${1:?}"
topsets="${2:?}"

shift ; shift
#$@ <-- other topsets, atm expect always exactly two

resdir_base="${_mydir}/results"
my_resdir_base="${resdir_base}/unique_sets"

rdir="${my_resdir_base}/${testid}"
test -d "$rdir" || mkdir -p "$rdir"

cd "${topsets}"

cmpset=''
curkeyfile=''

paths_worked=()

for cpd in "$@"; do
  i=0
  common=''

  if [ -n "$curkeyfile" ]; then
    testpaths="$(echo "${paths_worked[@]}" | tr ' ' '\n' )"
    must_work='true'
  else
    testpaths="$(find . -iname "sorted_unique_keys")"
    must_work=''
  fi

  if [ "${cpd:0:1}" == "+" ]; then
    cpd="${cpd:1}"
    common='true'
  fi

  while read keyset_file; do

    if [ -n "$curkeyfile" ]; then
      cmpsrc="${curkeyfile}"
    else
      cmpsrc="${keyset_file}"
    fi

    cmp_file="${origdir}/${cpd}/${keyset_file}"

    echo

    if ! [ -e "${cmp_file}" ]; then
      echo "WARNING: Could not test '${cmpsrc}', compare file '${cmp_file}' missing" >&2

      test -n "$must_work" || continue

      echo "ERROR: testing against this file must work!"
      exit 1
    fi

    if [ -e "$(dirname "${cmp_file}")/keys_complete" ]; then
      true
    else
      echo "WARNING: Testing '${cmpsrc}' against parent file '${cmp_file}' failing is inconclusive, as parent file is not a complete set of all possible coeffs" >&2
      
      test -n "$must_work" || continue

      echo "ERROR: testing against this file must work!"
      exit 1
    fi

    if [ "$i" -eq 0 ]; then
      source "$(dirname "$cmp_file")/analyse_meta" || exit "$?"
      cmpset="${cmpset}_${modules:?}"

      if [ -z "$common" ]; then
        resfile="${rdir}/unique_to${cmpset}"
      else
        resfile="${rdir}/common_with_${cmpset}"
      fi
    fi

    if [ -z "$curkeyfile" ]; then
      paths_worked+=("$keyset_file")
    fi

    if [ -z "$common" ]; then
      echo -n "Get sets unique to '${cmpsrc}' compared to '${cmp_file}' ..."
      ##unique="$(comm -23 "${cmpsrc}" "${cmp_file}")"
      comm -23 "${cmpsrc}" "${cmp_file}" >> "${resfile}"
      ##wc -l "${resfile}"
    else
      echo -n "Get sets common for '${cmpsrc}' and '${cmp_file}' ..."
      ##unique="$(comm -12 "${cmpsrc}" "${cmp_file}")"
      comm -12 "${cmpsrc}" "${cmp_file}" >> "${resfile}"
    fi

    ##if [ -z "${unique}" ]; then
    ##  echo "  no found, error!" >&2
    ##  exit 1
    ##fi

    echo "  ok!" >&2

    ##echo "$unique" >> "${resfile}"

    if [ -z "$common" ]; then
      ## note: as new unique stuff might not be unique compared to
      ##   prev test files we actually must redo unique testing for them
      for x in "${paths_worked[@]}"; do

        cat "${resfile}" | sort -u > "${resfile}_tmp"
        mv "${resfile}_tmp" "${resfile}"

	##set -x
        comm -23 "${resfile}" "${origdir}/${cpd}/${x}" > "${resfile}_tmp"
        mv "${resfile}_tmp" "${resfile}"
        ##wc -l "${resfile}"

      done

      ##badc="$(comm -12 "${resfile}" "${cmp_file}" | head -n5)"

      ##if [ -n "$badc" ]; then
      ##  echo "ERROR: bad common found:" >&2
      ##  echo "$badc" >&2
      ##  exit 1
      ##fi
    fi

    i=$((i+1))

  done <<<"$testpaths"

  cat "$resfile" | sort -u > "${resfile}_tmp2"
  mv "${resfile}_tmp2" "$resfile"

  curkeyfile="${resfile}"
done

ln -s "${curkeyfile}" "${rdir}/unique_to_all"

##echo
##echo "Test succesful, all tested keysets file of dir tree '${topsets}' are also coeff sets of dir tree '${parentkeys}' except for potential warnings"
##echo

