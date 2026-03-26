#!/bin/bash
set -euo pipefail

try_run() {
  local out
  if out="$("$@" 2>/dev/null | head -1)"; then
    echo "'$out'"
  fi
}

os_version() {
  {
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null
    echo "$PRETTY_NAME"
  }
}

os_arch() {
  uname -m
}

triplet() {
  gcc -dumpmachine
}

gcc_version() {
  gcc -dumpfullversion
}

gxx_version() {
  g++ -dumpfullversion
}

gfortran_version() {
  gfortran -dumpfullversion
}

python3_version() {
  python3 --version | awk '{print $2}'
}

root_version() {
  root-config --version
}

mg5_aMC_version() {
  echo 'exit' | mg5_aMC | grep -i version | sed 's/^.*version//i' | awk '{print $1}'
}

lhapdf_version() {
  lhapdf-config --version
}

eMELA_version() {
  eMELA-config --version
}

pythia8_version() {
  pythia8-config --version
}

fastjet_version() {
  fastjet-config --version
}

ma5_version() {
  ma5 --version | sed 's/^.*release//i' | sed 's/://g' | awk '{print $1}'
}

for f in \
  os_version \
  os_arch \
  triplet \
  gcc_version \
  gxx_version \
  gfortran_version \
  python3_version \
  root_version \
  mg5_aMC_version \
  lhapdf_version \
  eMELA_version \
  pythia8_version \
  fastjet_version \
  ma5_version; do
  echo "$f=$(try_run $f)"
done
