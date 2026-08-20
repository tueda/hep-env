#!/usr/bin/env bash

# Run the shared MG5 -> Pythia8 -> Delphes -> ROOT -> MA5 smoke workflow.
# This script runs inside the image and intentionally contains no
# Docker- or Apptainer-specific mount logic.
# cspell:ignore xtics ylabel

set -euo pipefail

smoke_dir=/work/hep-env-smoke
process_dir=$smoke_dir/process
run_dir=$process_dir/Events/run_01
ma5_output=$smoke_dir/ma5-output
smoke_log=$smoke_dir/smoke.log
lhapdf_log=$smoke_dir/lhapdf-check.log
mg5_log=$smoke_dir/mg5.log
ma5_log=$smoke_dir/ma5.log
root_log=$smoke_dir/root-check.log
histogram_log=$smoke_dir/histogram-check.log
smoke_events=${SMOKE_EVENTS:-1000}
smoke_runtime=${SMOKE_RUNTIME:-unknown}
delphes_events=0
events_with_jets=0
processed_events=0
histogram_1_entries=0
histogram_2_entries=0
histogram_3_entries=0
active_process_group=
current_stage=initialization
last_completed_stage=none
termination_signal=

stage() {
  printf '[smoke] %s\n' "$*" | tee -a "$smoke_log"
}

tail_log() {
  local path=$1

  if [[ -s $path ]]; then
    printf '\n[smoke] tail of %s\n' "$path" >&2
    tail -n 80 "$path" >&2
  fi
}

diagnose() {
  local status=$1

  trap - EXIT
  if ((status != 0)); then
    if [[ $termination_signal != SIGINT ]]; then
      tail_log "$lhapdf_log"
      tail_log "$mg5_log"
      tail_log "$run_dir/tag_1_pythia8.log"
      tail_log "$run_dir/tag_1_delphes.log"
      tail_log "$ma5_log"
      tail_log "$root_log"
      tail_log "$histogram_log"
    fi
    printf '\n[smoke] last completed stage: %s\n' \
      "$last_completed_stage" >&2
    if [[ $termination_signal == SIGINT ]]; then
      printf '[smoke] interrupted stage: %s\n' "$current_stage" >&2
      printf '[smoke] INTERRUPTED (SIGINT, status %d)\n' "$status" >&2
    elif [[ $termination_signal == SIGTERM ]]; then
      printf '[smoke] work directory: %s\n' "$smoke_dir" >&2
      printf '[smoke] terminated stage: %s\n' "$current_stage" >&2
      printf '[smoke] TERMINATED (SIGTERM, status %d)\n' "$status" >&2
    else
      printf '[smoke] work directory: %s\n' "$smoke_dir" >&2
      printf '[smoke] failed stage: %s\n' "$current_stage" >&2
      printf '[smoke] FAIL (status %d)\n' "$status" >&2
    fi
  fi
  exit "$status"
}

stop_active_process_group() {
  local status=$1
  local signal_name=$2
  local attempt

  termination_signal=$signal_name
  trap '' INT TERM
  if [[ -n $active_process_group ]]; then
    printf '[smoke] received %s; stopping active processes\n' \
      "$signal_name" >&2
    kill -TERM -- "-$active_process_group" 2>/dev/null || true
    for ((attempt = 0; attempt < 20; attempt++)); do
      if ! kill -0 -- "-$active_process_group" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 -- "-$active_process_group" 2>/dev/null; then
      kill -KILL -- "-$active_process_group" 2>/dev/null || true
    fi
    wait "$active_process_group" 2>/dev/null || true
    active_process_group=
  fi
  exit "$status"
}

run_logged() {
  local log=$1
  local status

  shift
  setsid "$@" <&0 >"$log" 2>&1 &
  active_process_group=$!
  if wait "$active_process_group"; then
    status=0
  else
    status=$?
  fi
  active_process_group=
  return "$status"
}

trap 'diagnose "$?"' EXIT
trap 'stop_active_process_group 130 SIGINT' INT
trap 'stop_active_process_group 143 SIGTERM' TERM

if [[ ! $smoke_events =~ ^[1-9][0-9]*$ ]]; then
  echo "SMOKE_EVENTS must be a positive integer: $smoke_events" >&2
  exit 2
fi
if [[ ! -d /work || ! -w /work ]]; then
  echo '/work must be a writable directory' >&2
  exit 1
fi
if [[ ! -d /data || ! -w /data ]]; then
  echo '/data must be a writable directory' >&2
  exit 1
fi
if [[ -e $smoke_dir || -L $smoke_dir ]]; then
  echo "$smoke_dir already exists" >&2
  exit 1
fi

mkdir "$smoke_dir"
cd "$smoke_dir"
touch "/data/.hep-env-smoke-write-test.$$"
rm "/data/.hep-env-smoke-write-test.$$"
last_completed_stage=$current_stage

current_stage='container setup'
stage 'checking container setup'
[[ $(readlink -f /opt/MG5_aMC/models) == /data/models ]]
grep -q '^auto_update = 0' /opt/MG5_aMC/input/mg5_configuration.txt
[[ ${MA5_NO_AUTOREBUILD:-} == 1 ]]

command -v setsid >/dev/null
fastjet-config --version >/dev/null
last_completed_stage=$current_stage

current_stage='LHAPDF validation'
lhapdf_data_dir=$(readlink -f "$(lhapdf-config --datadir)")
[[ $lhapdf_data_dir == /data/LHAPDF ]]
run_logged "$lhapdf_log" python3 - <<'PY'
import math
import os

import lhapdf

expected = "/data/LHAPDF"
paths = [os.path.realpath(path) for path in lhapdf.paths()]
if expected not in paths:
    raise SystemExit(f"LHAPDF paths do not contain {expected}: {paths}")

pdf = lhapdf.mkPDF("NNPDF23_lo_as_0130_qed", 0)
value = pdf.xfxQ(21, 0.1, 100.0)
if not math.isfinite(value) or value == 0.0:
    raise SystemExit(f"Unexpected LHAPDF evaluation result: {value}")
print(f"[smoke] LHAPDF member evaluation: {value:.8g}")
PY
last_completed_stage=$current_stage

current_stage='MG5, Pythia8, and Delphes'
cat >"$smoke_dir/mg5.cmd" <<EOF
import model sm
generate p p > t t~
output $process_dir
launch $process_dir
shower=Pythia8
detector=Delphes
analysis=OFF
set nevents $smoke_events
set lhc 13
set no_parton_cut
set use_syst False
EOF

stage "generating pp > t t~ with $smoke_events events"
started_at=$(date +%s)
run_logged "$mg5_log" mg5_aMC "$smoke_dir/mg5.cmd"
mg5_seconds=$(($(date +%s) - started_at))

grep -Fq 'Restrict model sm with file' "$mg5_log"
grep -Eq '[0-9]+ processes with [0-9]+ diagrams generated' "$mg5_log"
grep -Fq 'Running Pythia8' "$mg5_log"
grep -Fq 'Running Delphes' "$mg5_log"
grep -Fq 'delphes done' "$mg5_log"

pythia_log=$run_dir/tag_1_pythia8.log
delphes_log=$run_dir/tag_1_delphes.log
hepmc_file=$run_dir/tag_1_pythia8_events.hepmc.gz
delphes_file=$run_dir/tag_1_delphes_events.root
banner_file=$run_dir/run_01_tag_1_banner.txt

[[ -s $pythia_log ]]
[[ -s $delphes_log ]]
[[ -s $hepmc_file ]]
[[ -s $delphes_file ]]
[[ -s $banner_file ]]
gzip -t "$hepmc_file"
grep -Fq 'FastJetFinder' "$banner_file"
stage "MG5, Pythia8, and Delphes completed in ${mg5_seconds}s"
last_completed_stage=$current_stage

current_stage='Delphes ROOT validation'
stage 'checking the Delphes ROOT output'
run_logged "$root_log" python3 - \
  "$delphes_file" "$smoke_dir/root.env" <<'PY'
import sys

import ROOT

input_path, output_path = sys.argv[1:]
if ROOT.gSystem.Load("libDelphes") < 0:
    raise SystemExit("Could not load the Delphes ROOT dictionary")
for header in (
    "classes/DelphesClasses.h",
    "external/ExRootAnalysis/ExRootTreeReader.h",
):
    if not ROOT.gInterpreter.Declare(f'#include "{header}"'):
        raise SystemExit(f"Could not load the Delphes header: {header}")
root_file = ROOT.TFile.Open(input_path)
if not root_file or root_file.IsZombie():
    raise SystemExit(f"Could not open ROOT file: {input_path}")

metadata_tree = root_file.Get("Delphes")
if not metadata_tree:
    raise SystemExit("The Delphes tree is missing")
metadata_events = int(metadata_tree.GetEntries())
if metadata_events <= 0:
    raise SystemExit(f"The Delphes tree has {metadata_events} events")
if not metadata_tree.GetBranch("Jet"):
    raise SystemExit("The Jet branch is missing")
root_file.Close()

chain = ROOT.TChain("Delphes")
if chain.Add(input_path) != 1:
    raise SystemExit(f"Could not add the Delphes ROOT file: {input_path}")
tree_reader = ROOT.ExRootTreeReader(chain)
events = int(tree_reader.GetEntries())
if events != metadata_events:
    raise SystemExit(
        f"Delphes event-count mismatch: {metadata_events} != {events}"
    )
jet_branch = tree_reader.UseBranch("Jet")
events_with_jets = 0
for entry in range(events):
    tree_reader.ReadEntry(entry)
    if jet_branch.GetEntries() > 0:
        events_with_jets += 1
if events_with_jets <= 0:
    raise SystemExit("No event has a reconstructed jet")

with open(output_path, "w", encoding="ascii") as output:
    output.write(f"delphes_events={events}\n")
    output.write(f"events_with_jets={events_with_jets}\n")
print(f"[smoke] Delphes events: {events}")
print(f"[smoke] Events with reconstructed jets: {events_with_jets}")
PY
tee -a "$smoke_log" <"$root_log"
# The generated values are integers written by the Python assertion above.
# shellcheck disable=SC1091
source "$smoke_dir/root.env"
last_completed_stage=$current_stage

current_stage='MadAnalysis 5'
cat >"$smoke_dir/ma5.cmd" <<EOF
import $delphes_file as ttbar
set main.normalize = none
set main.stacking_method = normalize2one
plot N(j) 21 -0.5 20.5
plot PT(j[1]) 50 0 500 [PTordering]
plot MET 50 0 500
submit $ma5_output
EOF

# Hide LaTeX commands from MA5 while retaining the image's normal executable
# search path. MA5 still creates its HTML report and PNG plots.
filtered_bin=$smoke_dir/no-latex-bin
mkdir "$filtered_bin"
IFS=: read -r -a path_entries <<<"$PATH"
for path_entry in "${path_entries[@]}"; do
  [[ -d $path_entry ]] || continue
  while IFS= read -r -d '' executable; do
    executable_name=${executable##*/}
    case $executable_name in
    latex | pdflatex)
      continue
      ;;
    esac
    if [[ ! -e $filtered_bin/$executable_name &&
      ! -L $filtered_bin/$executable_name ]]; then
      ln -s "$executable" "$filtered_bin/$executable_name"
    fi
  done < <(find -L "$path_entry" -maxdepth 1 -type f -executable -print0 \
    2>/dev/null)
done

stage 'running MadAnalysis 5 in reconstructed-level mode'
started_at=$(date +%s)
run_logged "$ma5_log" env PATH="$filtered_bin" \
  MPLCONFIGDIR="$smoke_dir/matplotlib" \
  ma5 -R -f -s "$smoke_dir/ma5.cmd"
ma5_seconds=$(($(date +%s) - started_at))
stage "MadAnalysis 5 completed in ${ma5_seconds}s"

if ! grep -Fq 'MadAnalysis test program works.' "$ma5_log" &&
  ! grep -Fq 'Skipping rebuild because MA5_NO_AUTOREBUILD is set.' "$ma5_log"; then
  echo 'MA5 did not confirm reuse of its core libraries' >&2
  exit 1
fi
grep -Fq 'sample format: Delphes-ROOT file produced by Delphes.' "$ma5_log"
grep -Fq "Running 'SampleAnalyzer' over dataset 'ttbar'" "$ma5_log"
grep -Fq 'MA5-WARNING: pdflatex disabled.' "$ma5_log"
grep -Fq 'MA5-WARNING: latex disabled.' "$ma5_log"

histogram_file=$ma5_output/Output/SAF/_ttbar/MadAnalysis5job_0/Histograms/histos.saf
plot_dir=$ma5_output/Output/HTML/MadAnalysis5job_0
[[ -s $histogram_file ]]
[[ -s $plot_dir/selection_0.png ]]
[[ -s $plot_dir/selection_1.png ]]
[[ -s $plot_dir/selection_2.png ]]
last_completed_stage=$current_stage

current_stage='histogram validation'
run_logged "$histogram_log" python3 - \
  "$histogram_file" "$ma5_log" "$smoke_dir/histograms.env" \
  "$smoke_dir" <<'PY'
import math
import re
import sys

histogram_path, log_path, output_path, plot_data_dir = sys.argv[1:]
with open(histogram_path, encoding="utf-8") as source:
    saf = source.read()
blocks = re.findall(r"<Histo>(.*?)</Histo>", saf, flags=re.DOTALL)
if len(blocks) != 3:
    raise SystemExit(f"Expected 3 histograms, found {len(blocks)}")

expected_names = ["1_N", "2_PT", "3_MET"]
entries = []
for index, (block, expected_name) in enumerate(
    zip(blocks, expected_names, strict=True), start=1
):
    description = re.search(
        r"<Description>(.*?)</Description>", block, flags=re.DOTALL
    )
    name = (
        re.search(r'^\s*"([^"]+)"', description.group(1))
        if description
        else None
    )
    if not name or name.group(1) != expected_name:
        actual = name.group(1) if name else "missing"
        raise SystemExit(
            f"Histogram {index} name is {actual}, expected {expected_name}"
        )
    description_rows = [
        line.split("#", 1)[0].strip()
        for line in description.group(1).splitlines()
        if line.split("#", 1)[0].strip()
    ]
    if len(description_rows) < 2:
        raise SystemExit(f"Histogram {expected_name} has no bin description")
    try:
        number_of_bins_text, minimum_text, maximum_text = (
            description_rows[1].split()
        )
        number_of_bins = int(number_of_bins_text)
        minimum = float(minimum_text)
        maximum = float(maximum_text)
    except (ValueError, TypeError) as error:
        raise SystemExit(
            f"Histogram {expected_name} has an invalid bin description"
        ) from error
    if (
        number_of_bins <= 0
        or not math.isfinite(minimum)
        or not math.isfinite(maximum)
        or maximum <= minimum
    ):
        raise SystemExit(
            f"Histogram {expected_name} has an invalid bin description"
        )
    statistics = re.search(
        r"<Statistics>(.*?)</Statistics>", block, flags=re.DOTALL
    )
    data = re.search(r"<Data>(.*?)</Data>", block, flags=re.DOTALL)
    if not statistics or not data:
        raise SystemExit(f"Histogram {expected_name} has incomplete SAF data")
    statistic_rows = [
        line.split("#", 1)[0].strip()
        for line in statistics.group(1).splitlines()
        if line.split("#", 1)[0].strip()
    ]
    try:
        entry_values = [float(value) for value in statistic_rows[2].split()]
    except (IndexError, ValueError) as error:
        raise SystemExit(
            f"Histogram {expected_name} has invalid entry counts"
        ) from error
    if len(entry_values) != 2 or any(
        not math.isfinite(value) or value < 0 or not value.is_integer()
        for value in entry_values
    ):
        raise SystemExit(f"Histogram {expected_name} has invalid entry counts")
    histogram_entries = sum(int(value) for value in entry_values)
    data_rows = [
        [float(value) for value in line.split("#", 1)[0].split()]
        for line in data.group(1).splitlines()
        if line.split("#", 1)[0].strip()
    ]
    if len(data_rows) != number_of_bins + 2 or any(
        len(row) != 2 for row in data_rows
    ):
        raise SystemExit(f"Histogram {expected_name} has invalid bin data")
    all_bin_values = [
        positive - negative for positive, negative in data_rows
    ]
    if histogram_entries <= 0:
        raise SystemExit(f"Histogram {expected_name} has no entries")
    if not all(math.isfinite(value) for value in all_bin_values):
        raise SystemExit(f"Histogram {expected_name} has non-finite bins")
    normalization = sum(all_bin_values)
    if not math.isfinite(normalization) or normalization <= 0:
        raise SystemExit(
            f"Histogram {expected_name} has invalid normalization"
        )
    bin_values = [
        max(value, 0.0) / normalization for value in all_bin_values[1:-1]
    ]
    if not any(value != 0.0 for value in bin_values):
        raise SystemExit(f"Histogram {expected_name} has no nonzero bins")
    bin_width = (maximum - minimum) / number_of_bins
    with open(
        f"{plot_data_dir}/histogram-{index}.dat", "w", encoding="ascii"
    ) as plot_data:
        for bin_index, value in enumerate(bin_values):
            center = minimum + (bin_index + 0.5) * bin_width
            plot_data.write(f"{center:.12g} {value:.12g}\n")
    entries.append(histogram_entries)

with open(log_path, encoding="utf-8", errors="replace") as source:
    ma5_log = source.read()
match = re.search(r"Total number of processed events:\s*([0-9]+)", ma5_log)
if not match or int(match.group(1)) <= 0:
    raise SystemExit("Could not find a nonzero MA5 processed-event count")
processed_events = int(match.group(1))

with open(output_path, "w", encoding="ascii") as output:
    output.write(f"processed_events={processed_events}\n")
    for index, value in enumerate(entries, start=1):
        output.write(f"histogram_{index}_entries={value}\n")
print(f"[smoke] MA5 processed events: {processed_events}")
for name, value in zip(expected_names, entries, strict=True):
    print(f"[smoke] Histogram {name} entries: {value}")
PY
tee -a "$smoke_log" <"$histogram_log"
# The generated values are integers written by the Python assertion above.
# shellcheck disable=SC1091
source "$smoke_dir/histograms.env"
last_completed_stage=$current_stage

current_stage='terminal histogram rendering'
stage 'MA5 histograms (Y axis: Normalized entries)'
histogram_titles=('N(j)' 'Leading-jet PT [GeV]' 'MET [GeV]')
for index in "${!histogram_titles[@]}"; do
  histogram_number=$((index + 1))
  histogram_style=boxes
  if ((histogram_number == 1)); then
    histogram_style=impulses
  fi
  gnuplot <<EOF | tr -d '\f'
set terminal dumb size 78,18 mono
set title "${histogram_titles[$index]}"
set ylabel "Normalized entries"
set style fill solid 1.0
if ($histogram_number == 1) {
  set xrange [-0.5:20.5]
  set xtics 2
} else {
  set boxwidth 0.9 relative
}
unset key
plot "$smoke_dir/histogram-$histogram_number.dat" using 1:2 \
  with $histogram_style
EOF
done
last_completed_stage=$current_stage

current_stage='summary generation'
cat >"$smoke_dir/summary.env" <<EOF
smoke_runtime=$smoke_runtime
requested_events=$smoke_events
mg5_seconds=$mg5_seconds
ma5_seconds=$ma5_seconds
delphes_events=$delphes_events
events_with_jets=$events_with_jets
processed_events=$processed_events
histogram_1_entries=$histogram_1_entries
histogram_2_entries=$histogram_2_entries
histogram_3_entries=$histogram_3_entries
EOF

cat >"$smoke_dir/summary.md" <<EOF
| Result | Value |
| --- | ---: |
| Requested events | $smoke_events |
| Delphes events | $delphes_events |
| Events with jets | $events_with_jets |
| MA5 processed events | $processed_events |
| \`N(j)\` entries | $histogram_1_entries |
| Leading-jet \`PT\` entries | $histogram_2_entries |
| \`MET\` entries | $histogram_3_entries |
EOF

stage "PASS (${smoke_runtime})"
last_completed_stage=$current_stage
