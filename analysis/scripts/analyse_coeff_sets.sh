#!/usr/bin/env bash


_mydir="$(readlink -f "$0" | xargs dirname)"


fn_permres_cmd() {
  ##cat "$1" | awk '/----------/{flag=1;next}/---------/{flag=0}flag' | sed "s,^,$1  ,"
  cat "$1" | sed "s,^,$1 ; ,"
}

##fn_cleanup() {
##  if [ -n "$tmp_setfile" ]; then
##    test -e "$tmp_setfile" && rm -rf "$tmp_setfile"
##  fi
##}
##
##trap fn_cleanup EXIT


coeff_file="${1}"
pathfilter="${2}"
resfile="${3}"
resdir_base="${4:-${_mydir}/results}"

gendir_base="${resdir_base}/coeff_gen"
myres_base="${resdir_base}/coeff_stats"
##allmeta="${myres_base}/analyse_meta"

test -d "${myres_base}" || mkdir -p "${myres_base}"

duration_sumtime_start="$(date +%s)"

test -n "${resfile}" || resfile="${coeff_file}"


if [ -z "${coeff_file}" ]; then
  # on default analyse a file of all complete coeff sets
  coeff_file="${myres_base}/combined_sets_all_complete"
  test -n "${resfile}" || resfile="${coeff_file}"

  if [ -n "${pathfilter}" ]; then
    ##pathfilter=("-ipath" "$pathfilter")
    pathfilter=("-iregex" "$pathfilter")
  fi

  if ! [ -e "${resfile}" ]; then
    export -f fn_permres_cmd
    find "${gendir_base}" -iname "keys_complete" "${pathfilter[@]}"\
      -exec bash -c 'fn_permres_cmd "$0"' {} ";" > "${resfile}"
  fi

else

  if [ "${resfile}" != "${coeff_file}" ]; then
    cp "${coeff_file}" "${resfile}"
  fi

fi


bucket_dir="${myres_base}/buckets/$(basename "${resfile}")"
filemeta="${bucket_dir}/analyse_meta"

test -d "${bucket_dir}" || mkdir -p "${bucket_dir}"

rm -rf "${bucket_dir}/"*

cset_cnt=0

while read cset; do
  cset_cnt=$((cset_cnt+1))

  ## # trim cset
  ## cset="$(echo "$cset" | sed 's/^\s*//' | sed 's/\s*$//')"

  ##echo "" >> "${bucket_dir}/configs"
  ##echo "$cset" >> "${bucket_dir}/configs"
  ##echo "" >> "${bucket_dir}/configs"

  cfgs=""
  while read srcf; do
    if [ -z "$srcf" ]; then
      echo "ERROR: srcf ref empty" >&2
      exit 1
    fi

    pres="$(dirname "$srcf")/permutator_result"
    cfgs="${cfg}$(grep -e "	$cset\s*\$" "$pres" | awk '{print $3}')\n"

  done <<<"$(grep -e ";\s*$cset\s*\$" "${resfile}" \
    | awk '{print $1}' | sed 's/\s*;\s*$//')"

  ##echo "$(echo -e "$cfgs" | grep -v '^\s*$' | sort -u) [$cset]" >> "${bucket_dir}/configs"
  echo "$(echo -e "$cfgs" | grep -v '^\s*$' | sort -u | wc -l) [$cset]" >> "${bucket_dir}/cfgcnt"

  # check how many sets start with negative numbers
  if [ "${cset:0:1}" = "-" ]; then
    echo "$cset" >> "${bucket_dir}/start_neg"
  fi
  
  if echo "$cset" | grep -qv "-"; then
    # have only positive numbers
    echo "$cset" >> "${bucket_dir}/only_pos"
  elif echo "$cset" | grep -qv "\s[1-9]"; then
    # have only negative numbers
    echo "$cset" >> "${bucket_dir}/only_neg"
  fi

  # include zero
  if echo "$cset" | grep -q "\s0\(\s\|\$\)"; then
    echo "$cset" >> "${bucket_dir}/with_zero"
  fi

  cset_split="$(echo "$cset" | sed 's/\s\+/\n/g')"
  cset_negs="$(echo "$cset_split" | grep '^-')"
  cset_pos="$(echo "$cset_split" | grep '^[1-9]')"

  echo "[$cset]: $(echo "$cset_split" | awk '{_+=$1}END{printf "%0.2f\n",_/NR}')" >> "${bucket_dir}/set_avg"
  echo "[$cset]: $(echo "$cset_split" | sort -n | awk '{a[NR]=$0}END{print(NR%2==1)?a[int(NR/2)+1]:(a[NR/2]+a[NR/2+1])/2}')" >> "${bucket_dir}/set_median"

  # symmetrically checks
  negs_cnt=0
  pos_cnt=0

  if [ -n "${cset_negs}" ]; then
    negs_cnt="$(echo "$cset_negs" | wc -l)"
  fi

  if [ -n "${cset_pos}" ]; then
    pos_cnt="$(echo "$cset_pos" | wc -l)"
  fi

  if [ "${negs_cnt}" -gt "${pos_cnt}" ]; then
    echo "$cset" >> "${bucket_dir}/more_negs"
  elif [ "${negs_cnt}" -lt "${pos_cnt}" ]; then
    echo "$cset" >> "${bucket_dir}/more_pos"
  else
    echo "$cset" >> "${bucket_dir}/symmetrical"
  fi

  echo "$(echo "$cset_split" | wc -l) [$cset]" >> "${bucket_dir}/coef_cnt"

  # get max/min vals
  echo "$(echo "$cset_negs" | sort -n | head -1) [$cset]" >> "${bucket_dir}/neg_min"
  echo "$(echo "$cset_pos" | sort -n | tail -1) [$cset]" >> "${bucket_dir}/pos_max"

  # # all the above with or without zero
  # # have odd numbers
  # # relation odd to even
##done <<<"$(cat "${resfile}" | awk -F';' '{print $2}' | sed 's/^\s*//' | sed 's/\s*$//' | sort -u | shuf -n 2000000)"
done <<<"$(cat "${resfile}" | awk -F';' '{print $2}' | sed 's/^\s*//' | sed 's/\s*$//' | sort -u )"
## ##done <<<"$(cat <<'EOOF'
## ##-1 -5 -21 0 1 333 10
## ##-1 0 1 12
## ##EOOF
## ##)"
## 
## ##-1 0
## ##-1 0 1

start_neg=0
start_neg_perc=0

if [ -e "${bucket_dir}/start_neg" ]; then
  start_neg="$(cat "${bucket_dir}/start_neg" | wc -l)"
  start_neg_perc="$(bc <<<"scale=3; $start_neg / $cset_cnt")"
fi

only_neg=0
only_neg_perc=0

if [ -e "${bucket_dir}/only_neg" ]; then
  only_neg="$(cat "${bucket_dir}/only_neg" | wc -l)"
  only_neg_perc="$(bc <<<"scale=3; $only_neg / $cset_cnt")"
fi

only_pos=0
only_pos_perc=0

if [ -e "${bucket_dir}/only_pos" ]; then
  only_pos="$(cat "${bucket_dir}/only_pos" | wc -l)"
  only_pos_perc="$(bc <<<"scale=3; $only_pos / $cset_cnt")"
fi

with_zero=0
with_zero_perc=0

if [ -e "${bucket_dir}/with_zero" ]; then
  with_zero="$(cat "${bucket_dir}/with_zero" | wc -l)"
  with_zero_perc="$(bc <<<"scale=3; $with_zero / $cset_cnt")"
fi

symmetrical=0
symmetrical_perc=0

if [ -e "${bucket_dir}/symmetrical" ]; then
  symmetrical="$(cat "${bucket_dir}/symmetrical" | wc -l)"
  symmetrical_perc="$(bc <<<"scale=3; $symmetrical / $cset_cnt")"
fi

more_negs=0
more_negs_perc=0

if [ -e "${bucket_dir}/more_negs" ]; then
  more_negs="$(cat "${bucket_dir}/more_negs" | wc -l)"
  more_negs_perc="$(bc <<<"scale=3; $more_negs / $cset_cnt")"
fi

more_pos=0
more_pos_perc=0

if [ -e "${bucket_dir}/more_pos" ]; then
  more_pos="$(cat "${bucket_dir}/more_pos" | wc -l)"
  more_pos_perc="$(bc <<<"scale=3; $more_pos / $cset_cnt")"
fi

duration_sumtime_end="$(date +%s)"
duration_sum=$(( duration_sumtime_end - duration_sumtime_start ))

cat > "${filemeta}" <<EOOF
coef_sets: ${cset_cnt}

start_neg: ${start_neg_perc} (${start_neg})
with_zero: ${with_zero_perc} (${with_zero})

only_neg: ${only_neg_perc} (${only_neg})
only_pos: ${only_pos_perc} (${only_pos})

symmetrical: ${symmetrical_perc} (${symmetrical})
more_neg: ${more_negs_perc} (${more_negs})
more_pos: ${more_pos_perc} (${more_pos})

coefcnt_max: $(cat "${bucket_dir}/coef_cnt" | sort -k 1 -n | tail -1 )
coefcnt_min: $(cat "${bucket_dir}/coef_cnt" | sort -k 1 -n | head -1 )

pos_max: $(cat "${bucket_dir}/pos_max" | sort -k 1 -n | tail -1 )
neg_min: $(cat "${bucket_dir}/neg_min" | sort -k 1 -n | head -1 )

cfgcnt_max: $(cat "${bucket_dir}/cfgcnt" | sort -k 1 -n | tail -1 )
cfgcnt_min: $(cat "${bucket_dir}/cfgcnt" | sort -k 1 -n | head -1 )
cfgcnt_avg: $(cat "${bucket_dir}/cfgcnt" | awk '{_+=$1}END{printf "%0.2f\n",_/NR}' )
cfgcnt_median: $(cat "${bucket_dir}/cfgcnt" | sort -k 1 -n|awk '{a[NR]=$1}END{print(NR%2==1)?a[int(NR/2)+1]:(a[NR/2]+a[NR/2+1])/2}')

duration: ${duration_sum}s
time_per_set: $(bc <<<"scale=4; $duration_sum / $cset_cnt")s
EOOF

