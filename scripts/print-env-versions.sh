#!/bin/bash
set -euo pipefail

# spell-checker: ignore -dumpfullversion
# spell-checker: ignore -dumpmachine
# spell-checker: ignore -dumpversion
# spell-checker: ignore clangxx
# spell-checker: ignore Cython
# spell-checker: ignore CUDACPP
# spell-checker: ignore Delphes
# spell-checker: ignore eMELA
# spell-checker: ignore FastJet
# spell-checker: ignore flang
# spell-checker: ignore gfortran
# spell-checker: ignore gsub
# spell-checker: ignore hepstats
# spell-checker: ignore ipykernel
# spell-checker: ignore IPython
# spell-checker: ignore LHAPDF
# spell-checker: ignore Matplotlib
# spell-checker: ignore NetworkX
# spell-checker: ignore Numba
# spell-checker: ignore NumPy
# spell-checker: ignore rustc
# spell-checker: ignore scikit-image
# spell-checker: ignore scikit-learn
# spell-checker: ignore SciPy
# spell-checker: ignore seaborn
# spell-checker: ignore statsmodels
# spell-checker: ignore SymPy
# spell-checker: ignore tolower
# spell-checker: ignore xarray
# spell-checker: ignore Zarr

try_run() {
  local out
  IFS= read -r out < <("$@" 2>/dev/null) || [ -n "$out" ] || return 0
  if [[ "$out" =~ ^[A-Za-z0-9._,-]*$ ]]; then
    printf '%s\n' "$out"
  else
    printf "'%s'\n" "$out"
  fi
}

first_line() {
  sed -n '1p'
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

bash_version() {
  echo "$BASH_VERSION"
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

clang_version() {
  clang -dumpversion
}

clangxx_version() {
  clang++ -dumpversion
}

flang_version() {
  flang -dumpversion
}

perl_version() {
  perl -e 'printf "%vd\n", $^V'
}

python3_version() {
  python3 --version | awk '{print $2}'
}

pip3_library_versions() {
  python3 -m pip list 2>/dev/null |
    grep -Ei '^(awkward|cython|hepstats|ipykernel|ipython|matplotlib|networkx|numba|numpy|pandas|polars|scikit-image|scikit-learn|scipy|seaborn|statsmodels|sympy|uproot|vector|xarray|zarr) ' |
    awk '{gsub("-", "_", $1); $1=tolower($1); print "python3_" $1 "_version=" $2}'
}

ruby_version() {
  ruby --version | awk '{print $2}'
}

node_version() {
  node --version | sed 's/^v//'
}

rustc_version() {
  rustc --version | awk '{print $2}'
}

go_version() {
  go version | awk '{print $3}' | sed 's/^go//'
}

julia_version() {
  julia --version | sed 's/^.*version//i' | awk '{print $1}'
}

curl_version() {
  curl --version | first_line | awk '{print $2}'
}

wget_version() {
  wget --version | first_line | awk '{print $3}'
}

git_version() {
  git --version | sed 's/^.*version//i' | awk '{print $1}'
}

make_version() {
  make --version | first_line | awk '{print $3}'
}

cmake_version() {
  cmake --version | first_line | sed 's/^.*version//i' | awk '{print $1}'
}

meson_version() {
  meson --version
}

autoconf_version() {
  autoconf --version | first_line | awk '{print $4}'
}

automake_version() {
  automake --version | first_line | awk '{print $4}'
}

libtool_version() {
  libtool --version | first_line | awk '{print $4}'
}

m4_version() {
  m4 --version | first_line | awk '{print $4}'
}

ninja_version() {
  ninja --version
}

nano_version() {
  nano --version | first_line | sed 's/^.*version//i' | awk '{print $1}'
}

vim_version() {
  vim --version | first_line | awk '{print $5}'
}

nvim_version() {
  nvim --version | first_line | awk '{print $2}' | sed 's/^v//'
}

emacs_version() {
  emacs --version | first_line | awk '{print $3}'
}

form_version() {
  form -v | first_line | awk '{print $2}'
}

root_version() {
  root-config --version
}

mg5_aMC_version() {
  echo 'exit' | mg5_aMC | grep -i version | first_line | sed 's/^.*version//i' | awk '{print $1}'
}

cudacpp_version() {
  awk '$1 == "cudacpp_version" { print $3; exit }' \
    "$(dirname "$(command -v mg5_aMC)")/../PLUGIN/CUDACPP_OUTPUT/VERSION.txt"
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

delphes_version() {
  awk '/^[0-9]+(\.[0-9]+)*:/ { sub(/:.*/, ""); print; exit }' "$(dirname "$(command -v DelphesHepMC3)")/CHANGELOG"
}

ma5_version() {
  ma5 --version | sed 's/^.*release//i' | sed 's/://g' | awk '{print $1}'
}

for f in \
  os_version \
  os_arch \
  triplet \
  bash_version \
  gcc_version \
  gxx_version \
  gfortran_version \
  clang_version \
  clangxx_version \
  flang_version \
  perl_version \
  python3_version \
  ruby_version \
  node_version \
  rustc_version \
  go_version \
  julia_version \
  curl_version \
  wget_version \
  git_version \
  make_version \
  cmake_version \
  meson_version \
  ninja_version \
  autoconf_version \
  automake_version \
  libtool_version \
  m4_version \
  nano_version \
  vim_version \
  nvim_version \
  emacs_version \
  form_version \
  root_version \
  mg5_aMC_version \
  cudacpp_version \
  lhapdf_version \
  eMELA_version \
  pythia8_version \
  fastjet_version \
  delphes_version \
  ma5_version; do
  v=$(try_run "$f")
  if [ -n "$v" ]; then
    echo "$f=$v"
    if [ "$f" = "python3_version" ]; then
      pip3_library_versions || :
    fi
  fi
done
