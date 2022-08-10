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
subkeys="${1:?}"
parentkeys="${2:?}"

##resdir_base="${3:-${_mydir}/results}"
##my_resdir_base="${resdir_base}/same_coef_configs"


cd "${subkeys}"

while read keyset_file; do
  cmp_file="${origdir}/${parentkeys}/${keyset_file}"

  echo

  if ! [ -e "${cmp_file}" ]; then
    echo "WARNING: Could not test '${subkeys}/${keyset_file}', parent compare file '${cmp_file}' missing" >&2
    continue
  fi

  echo -n "Are all coeff sets of '${subkeys}/${keyset_file}' also part of '${cmp_file}' ..."
  missings="$(comm -23 "${keyset_file}" "${cmp_file}")" ##| head -n160000)"

  if [ -z "${missings}" ]; then
    echo "  yes!"
    continue
  fi

  echo "  no!"

  echo "Missing ($(echo "${missings}" | wc -l) / $(wc -l "${keyset_file}")):"
  echo "${missings}" | head -n20
  echo

  if [ -e "$(dirname "${cmp_file}")/keys_complete" ]; then
    true
    ##exit 1
  else
    echo "WARNING: Testing '${subkeys}/${keyset_file}' against parent file '${cmp_file}' failing is inconclusive, as parent file is not a complete set of all possible coeffs" >&2
  fi

done <<<"$(find . -iname "sorted_unique_keys")"


##echo
##echo "Test succesful, all tested keysets file of dir tree '${subkeys}' are also coeff sets of dir tree '${parentkeys}' except for potential warnings"
##echo

