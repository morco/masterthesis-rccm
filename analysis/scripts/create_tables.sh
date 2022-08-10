#!/usr/bin/env bash

_mydir="$(readlink -f "$0" | xargs dirname)"


resfile="${1:?}"
target="${2:?}"
recfgmode="${3}"
hwstats_dir="${4:-${_mydir}/results/hw_stats}"

resdir="$(dirname "${resfile}")"

##if [ -e "${resfile}" ]; then
##  echo "skip already existing result table file '${resfile}'"
##  exit
##fi

test -d "${resdir}" || mkdir -p "${resdir}"

if ! [ -e "${resfile}" ]; then
  cat > "${resfile}" <<'EOOF'
testcat, modules, coeffset, cstruct, target, cfgstr, max-shift, wsize-in, freq, clbs, luts, ffs, dsps, fmax, logic-levels, power (total), power (static), power (dynamic)
EOOF
fi

# expect one or more cfg strings on stdin, one per line
while read cfgmap_line; do
  cfgstr="$(echo "${cfgmap_line}" | awk -F';' '{print $1}' | sed 's/^\s*//' | sed 's/\s*$//')"
  srcfile="$(echo "${cfgmap_line}" | awk -F';' '{print $2}' | sed 's/^\s*//' | sed 's/\s*$//')"
  cset="$(echo "${cfgmap_line}" | awk -F';' '{print $3}' | sed 's/^\s*//' | sed 's/\s*$//')"

  cstr_normed="$(echo "${cfgstr}" | tr '-' '_' | tr ':' '_')"

  srcdir="$(dirname "${srcfile}")"
  srcmeta="${srcdir}/analyse_meta"

  source "${srcmeta}"

  basedir="${hwstats_dir}/${target}"

  if [ -n "$recfgmode" ]; then
    basedir="${basedir}/recfg"
  fi

  cfgstats="$(find "${basedir}" -ipath "*/${cstr_normed}/*" -iname "vivado_analyse.log")"

  if [ -z "${cfgstats}" ]; then
    echo "ERROR: failed to find any results for cfg '${cfgstr}' (${cstr_normed}) inside '${basedir}'"  >&2
    exit 1
  fi

  while read statsfile; do

    if [ -n "$recfgmode" ]; then
      # get actual testcategory (special recfg mode from filepath
      testcat="$(dirname "$statsfile" | xargs dirname | xargs dirname | xargs basename)"
    fi

    # get wsize and freq from path
    wsize="$(echo "$statsfile" | grep -o 'wsize_[0-9]\+' | grep -o '[0-9]\+' )"
    freq="$(echo "$statsfile" | grep -o 'freq_[0-9]\+' | grep -o '[0-9]\+' )"

    # get stats from statfile
    stat_clb="$(grep -i -e 'clbs:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_lut="$(grep -i -e 'luts:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_ff="$(grep -i -e 'ffs:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_dsp="$(grep -i -e 'dsps:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_fmax="$(grep -i -e 'fmax:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_loglvl="$(grep -i -e 'logic levels:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_powtotal="$(grep -i -e 'total power:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_powstatic="$(grep -i -e 'static power:' "${statsfile}" | awk -F':' '{print $2}' )"
    stat_powdynamic="$(grep -i -e 'dynamic power:' "${statsfile}" | awk -F':' '{print $2}' )"

    cat >> "${resfile}" <<EOOF
${testcat}, $(echo "$modules" | tr ',' ' '), ${cset}, ${connect}, ${target}, ${cfgstr}, ${max_shift}, ${wsize}, ${freq}, ${stat_clb}, ${stat_lut}, ${stat_ff}, ${stat_dsp}, ${stat_fmax}, ${stat_loglvl}, ${stat_powtotal}, ${stat_powstatic}, ${stat_powdynamic}
EOOF
  done <<<"${cfgstats}"

done

