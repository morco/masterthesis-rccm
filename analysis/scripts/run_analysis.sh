#!/usr/bin/env bash

#
# from a given input config runs flopoco, auto generate a minimal wrapper code around generated for registers, run vivado scripts with the result
#

PARALLEL_RUNS=6

fn_cleanup() {
  # kill all subjobs when this is stopped
  pkill -P $$
}

trap fn_cleanup EXIT


_mydir="$(readlink -f "$0" | xargs dirname)"

elysia_bin="${_mydir}/../elysia/elysia"
vivado_run="${_mydir}/vivado/synth_scripts/scripts/synthesize_vivado.py"
vivado_analyse="${_mydir}/vivado/synth_scripts/scripts/analyze_results_vivado.py"


fn_run_test() {
  local freq="${1:?}"
  local ws="${2:?}"
  local resdir_base="${3:?}"
  local cstr_normed="${4:?}"

  local duration_start="$(date +%s)"

  local resdir="${resdir_base}/wsize_${ws}/freq_${freq}"
  local testfile="${resdir}/flopoco.vhd"
  local analyse_resfile="${resdir}/vivado_analyse.log"
  local analyse_meta="${resdir}/analyse_meta"

  local pmap_extra=''

  ##local entname="$(cat "${testfile}" | grep -i "entity RCCM_[0-9]" | awk '{print $2}')"
  ##resdir_synth="${resdir}/vivado/${entname}_${target}_${freq}"

  ##echo ""
  ##"${vivado_analyse}" "${resdir_synth}" "" "${entname}" 1 0 | tee "${analyse_resfile}"

  if [ -e "${analyse_meta}" ]; then
    echo "analysis meta file '${analyse_meta}' exists already, skip this hw analysis, delete this file first if you want to redo a previous analysis"
    return 0
  fi

  ## run flopoco to create operator vhdl code
  test -d "${resdir}" || mkdir -p "${resdir}"

if [ "$cstr_normed" = "genmult" ]; then

  local usedsp="yes"

  if [ "$ds" -eq 0 ]; then
    usedsp="no"
  fi

  local entname="generic_naive_mult"
  local cfsize=$((mxs + 1))
  local outsize=$((ws + mxs + 1))

  local invec="std_logic_vector($ws - 1 downto 0)"
  local outvec="std_logic_vector($outsize - 1 downto 0)"

  local portdef="$(cat <<EOOF
  port (
    clk    : in std_logic;
    X  : in ${invec};
    s  : in std_logic_vector($cfsize - 1 downto 0);
    Y  : out ${outvec});
EOOF
)"

  ## create simple generic multadder vhdl code
  cat > "${testfile}" <<EOOF

--------------------------------------------------------------------------------
--
-- script auto generated generic multiplier
-- 
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
library work;

entity ${entname} is
${portdef}
  attribute use_dsp : string;
end entity ${entname};

architecture generic_naive_mult_arch of ${entname} is
  attribute use_dsp of generic_naive_mult_arch : architecture is "$usedsp";
begin

  Y <= std_logic_vector(signed(X) * signed(s));

end architecture;

EOOF

elif [ "$cstr_normed" = "genadd" ]; then

  local entname="generic_naive_add"
  local cfsize=$((ws + mxs + 1))
  local outsize=$((ws + mxs + 1))

  local invec="std_logic_vector($ws - 1 downto 0)"
  local outvec="std_logic_vector($outsize - 1 downto 0)"

  local portdef="$(cat <<EOOF
  port (
    clk    : in std_logic;
    X  : in ${invec};
    s  : in std_logic_vector($cfsize - 1 downto 0);
    Y  : out ${outvec});
EOOF
)"

  ## create simple generic adder vhdl code
  cat > "${testfile}" <<EOOF

--------------------------------------------------------------------------------
--
-- script auto generated generic adder
-- 
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
library work;

entity ${entname} is
${portdef}
end entity ${entname};

architecture generic_naive_add_arch of ${entname} is
begin

  Y <= std_logic_vector(signed(X) + signed(s));

end architecture;

EOOF

else # standard rccm case
  local extra_args=()

  if [ -n "$recfgmode" ]; then
    extra_args+=("recfgType=${ds}")

    if echo "${cfgstr}" | grep -q ':'; then

    if [ "$ds" = "ring" ]; then
      pmap_extra="$(cat <<'EOOF'
cfgclk => cfgclk,
cfgce => cfgce,
EOOF
)"
    else
      pmap_extra="$(cat <<'EOOF'
cfgclk => cfgclk,
cfgce => cfgce,
cfgsel => cfgsel,
EOOF
)"
    fi
    fi

  fi

  if [ "${target}" == "versal" ]; then
    extra_args+=("target=${target}")
  fi

  ## note: as elysia creates some files inside cwd cwd should be in result dir for this call
  (
    cd "${resdir}"
    "${elysia_bin}" --flopoco Rccm wIn=${ws} frequency=${freq} config="${cfgstr}" "${extra_args[@]}" outputFile="${testfile}"
  )
  local rc="$?"

  if [ "${rc}" -ne 0 ]; then
    echo "ERROR: flopoco rccm creation failed" >&2
    return "${rc}"
  fi

  ## collect import infos from generated code
  local entname="$(cat "${testfile}" | grep -i "entity RCCM_[0-9]" | awk '{print $2}')"
  local portdef="$(cat "${testfile}" | awk '/entity RCCM_[0-9]/{flag=1;next}/end entity/{flag=0}flag')"
  local freq="$(echo "${entname}" | grep -io "_f[0-9]\+_" | grep -o '[0-9]\+')"

  local invec="$(echo "${portdef}" | grep -i 'x\s*:\s*in' | grep -io 'std_logic_vec[^)]*)')"
  local outvec="$(echo "${portdef}" | grep -i 'y\s*:\s*out' | grep -io 'std_logic_vec[^)]*)')"

fi

  ## attach custom wrapper module vhdl code file
  cat >> "${testfile}" <<EOOF

--------------------------------------------------------------------------------
--
-- script auto generated sim wrapper for putting register before and after operator
-- 
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
library work;

entity RCCM_SIMU_WRAPPER is
${portdef}
end entity;

architecture arch of RCCM_SIMU_WRAPPER is
  component ${entname} is
  ${portdef}
  end component;

  signal  reg_input : ${invec};
  signal reg_output : ${outvec};

begin

   process (clk)
   begin
       if clk'EVENT and clk = '1' then
          reg_input <= X;
       end if;
   end process;


   rccm_inst : ${entname}
      port map ( clk  => clk,
                 X => reg_input,
                 ${pmap_extra}
                 s => s,
                 Y => reg_output);


   process (clk)
   begin
       if clk'EVENT and clk = '1' then
          Y <= reg_output;
       end if;
   end process;

end architecture;

EOOF

if [ "$cstr_normed" = "genmult" ]; then
  entname="genmult"
elif [ "$cstr_normed" = "genadd" ]; then
  entname="genadd"
fi

  ## run vivado synth + implement
  local resdir_synth="${resdir}/vivado"

  if ! [ -e "${analyse_resfile}" ]; then
    "${vivado_run}" -i -v "${testfile}" -w "${resdir_synth}" \
      -e "${entname}" -t "${target}" -f "${freq}"

    rc="$?"

    if [ "${rc}" -ne 0 ]; then
      echo "ERROR: vivado rccm synth failed" >&2
      return "${rc}"
    fi

  fi

  ## analyse vivado results
  resdir_synth="${resdir}/vivado/${entname}_${target}_${freq}"

  echo ""
  "${vivado_analyse}" "${resdir_synth}" "" "${entname}" 1 0 | tee "${analyse_resfile}"

  rc="$?"

  if [ "${rc}" -ne 0 ]; then
    echo "ERROR: vivado rccm analyse failed" >&2
    return "${rc}"
  fi

echo "break"
exit
  local duration_end="$(date +%s)"

  cat > "${analyse_meta}" <<EOOF
duration: $(( duration_end - duration_start ))s
word_size: ${ws}

max_shift: ${mxs}
dsp: ${ds}
recfg_type: ${ds}
EOOF

  echo ""
  cat "${analyse_meta}"
}


target="${1:?}"
cfgstr="${2:?}"

recfgmode="${3}"

resdir_base="${4:-${_mydir}/results}"

##target="virtex7"
##cfgstr="HM1-C1-A0124-012-0"

doshifts=''
declare -a dsps=(0)

if [ "${cfgstr}" = "genmult" ]; then
  cstr_normed="${cfgstr}"
  myres_base_pre="${resdir_base}/hw_stats/${target}/${cstr_normed}"
  doshifts='true'
  allmeta="${myres_base_pre}/analyse_meta"
  declare -a dsps=(0 1)
elif [ "${cfgstr}" = "genadd" ]; then
  cstr_normed="${cfgstr}"
  myres_base_pre="${resdir_base}/hw_stats/${target}/${cstr_normed}"
  doshifts='true'
  allmeta="${myres_base_pre}/analyse_meta"
else
  cstr_normed="$(echo "${cfgstr}" | sed 's/:/_/g' | sed 's/-/_/g')"
  cfgbucket="${cstr_normed:0:10}"
  myres_base="${resdir_base}/hw_stats/${target}/${cfgbucket}/${cstr_normed}"
  allmeta="${myres_base}/analyse_meta"
fi

if [ -n "$recfgmode" ]; then
  # reuse dsps array for recfg mode switching
  declare -a dsps=(ring select selectLowEnergy)
  myres_base_pre="${resdir_base}/hw_stats/${target}/recfg/${cstr_normed}"
  allmeta="${myres_base_pre}/analyse_meta"
fi

duration_sumtime_start="$(date +%s)"


if [ -e "${allmeta}" ]; then
  echo "allmeta file '${allmeta}' exists already, skip this hw analysis run, delete this file first if you want to redo a previous analysis run"
  exit 0
fi

declare -a word_sizes=(4 5 6 7 8 "10" "12" "16")
declare -a frequencies=(200 400 600)
##declare -a word_sizes=(16)
##declare -a frequencies=(600)

declare -a shifts=(1)

if [ -n "$doshifts" ]; then
  declare -a shifts=(2 3 4 5 6)
  ##declare -a shifts=(6)
fi

pids=()

for ds in ${dsps[@]}; do
for mxs in ${shifts[@]}; do

if [ "${cfgstr}" = "genmult" ]; then
  myres_base="${myres_base_pre}/dsp_${ds}/mxs_${mxs}"
elif [ "${cfgstr}" = "genadd" ]; then
  myres_base="${myres_base_pre}/mxs_${mxs}"
fi

if [ -n "$recfgmode" ]; then
  myres_base="${myres_base_pre}/recfg_${ds}"
fi

for ws in ${word_sizes[@]}; do
  for freq in ${frequencies[@]}; do

    fn_run_test "$freq" "$ws" "$myres_base" "$cstr_normed" &
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
done
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

