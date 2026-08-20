FROM hepdock/root:6.34.02-ubuntu24.04

LABEL org.opencontainers.image.source="https://github.com/tueda/hep-env"
LABEL org.opencontainers.image.description="Container image for high-energy physics tools"
LABEL org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /opt
ENV LANG=C.UTF-8

# Building LHAPDF6 requires: cython3
# Python 3.12 f2py for MG5 reweighting/MadSpin on-shell mode requires: meson
# Building Pythia8 requires: rsync
# Building Delphes (from MadAnalysis5) requires: tcl
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    cython3=3.0.* \
    ghostscript=10.02.* \
    gnuplot-nox=6.0.* \
    libboost-all-dev=1.83.* \
    meson=1.3.* \
    pigz=2.* \
    python3-lxml=5.2.* \
    python3-matplotlib=3.6.* \
    python3-pip=24.* \
    python3-requests=2.31.* \
    python3-scipy=1.11.* \
    python3-semantic-version=2.10.* \
    rsync=3.2.* \
    tcl=8.6.* \
    texlive-latex-base=2023.* \
    texlive-latex-recommended=2023.* \
    vim=2:9.1.* \
    && rm -rf /var/lib/apt/lists/*

# MadAnalysis5 dependencies.
RUN wget -nv https://raw.githubusercontent.com/MadAnalysis/madanalysis5/refs/heads/main/requirements.txt \
    && python3 -m pip install --no-cache-dir --break-system-packages -r requirements.txt \
    && rm -f requirements.txt

ARG MG5_URL=https://launchpad.net/mg5amcnlo/3.0/3.7.x/+download/MG5_aMC_v3.7.2.tar.gz
ARG MG5_SHA256=278c447ffb3b2b6fe22fe1214bd74efc971058912053d6553299e5752e2d5648

ARG MG5_DIR=/opt/MG5_aMC
ARG HEPTOOLS_DIR=$MG5_DIR/HEPTools
ARG MA5_DIR=$HEPTOOLS_DIR/madanalysis5/madanalysis5
ARG DATA_DIR=/data

ENV MG5_NO_REFRESH_HEPTOOLS_INSTALLERS=1
ENV MA5_NO_AUTOREBUILD=1

RUN mkdir $DATA_DIR

# Install MadGraph5_aMC@NLO.
# We exclude macOS metadata files.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/mg5amcnlo/allow-skipping-heptools-installers-refresh,target=/tmp/patches1,readonly \
    wget -nv -O mg5.tar.gz "$MG5_URL" \
    && echo "$MG5_SHA256  mg5.tar.gz" | sha256sum -c - \
    && tar \
    --exclude='._*' \
    --exclude='*/._*' \
    --exclude='.DS_Store' \
    --exclude='*/.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='__MACOSX/*' \
    --exclude='*/__MACOSX' \
    --exclude='*/__MACOSX/*' \
    -xzf mg5.tar.gz \
    && rm -f mg5.tar.gz \
    && mv MG5_* MG5_aMC \
    && /tmp/apply-patches.sh /tmp/patches1 $MG5_DIR \
    && mv $MG5_DIR/models $DATA_DIR \
    && ln -s $DATA_DIR/models $MG5_DIR/models

# Disable automatic updates.
RUN echo "n" | $MG5_DIR/bin/mg5_aMC \
    && echo "set auto_update 0" | $MG5_DIR/bin/mg5_aMC \
    && grep -q "^auto_update = 0 #" $MG5_DIR/input/mg5_configuration.txt

# Enable automatic Python2 -> Python3 model conversion.
RUN echo "set auto_convert_model T" | $MG5_DIR/bin/mg5_aMC \
    && grep -q "^auto_convert_model = True" $MG5_DIR/input/mg5_configuration.txt

# Enable pigz.
RUN echo "set use_pigz True" | $MG5_DIR/bin/mg5_aMC \
    && grep -q "^use_pigz = True #" $MG5_DIR/input/mg5_configuration.txt

# Set the HEPTools installation directory using the absolute path.
# Note that https://github.com/mg5amcnlo/mg5amcnlo/commit/130e38c sets
# the default value to './HEPTools'.
RUN echo "heptools_install_dir = $HEPTOOLS_DIR" >>"$MG5_DIR/input/mg5_configuration.txt"

# Install LHAPDF6.
# Since heptools_install_dir is set, the configuration file is written
# under $XDG_CONFIG_HOME.
# Note that this step downloads HEPToolsInstallers.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/HEPToolsInstallers/install-emela-boost-path,target=/tmp/patches1,readonly \
    --mount=type=bind,source=patches/HEPToolsInstallers/update-hepmc-config-guess,target=/tmp/patches2,readonly \
    --mount=type=bind,source=patches/HEPToolsInstallers/ma5-success-detection,target=/tmp/patches3,readonly \
    --mount=type=bind,source=patches/lhapdf/migrate-to-requiring-py3,target=/tmp/patches4,readonly \
    echo "install lhapdf6" | XDG_CONFIG_HOME="$MG5_DIR/input" MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^lhapdf_py3 = $HEPTOOLS_DIR/lhapdf6_py3/bin/lhapdf-config #" $MG5_DIR/input/mg5_configuration.txt \
    && /tmp/apply-patches.sh /tmp/patches1 $HEPTOOLS_DIR/HEPToolsInstallers \
    && /tmp/apply-patches.sh /tmp/patches2 $HEPTOOLS_DIR/HEPToolsInstallers \
    && /tmp/apply-patches.sh /tmp/patches3 $HEPTOOLS_DIR/HEPToolsInstallers \
    && /tmp/apply-patches.sh /tmp/patches4 $HEPTOOLS_DIR/lhapdf6_py3 \
    && mv $HEPTOOLS_DIR/lhapdf6_py3/share/LHAPDF $DATA_DIR \
    && ln -s $DATA_DIR/LHAPDF $HEPTOOLS_DIR/lhapdf6_py3/share/LHAPDF

# Install eMELA.
RUN echo "install eMELA" | XDG_CONFIG_HOME="$MG5_DIR/input" MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^eMELA = $HEPTOOLS_DIR/bin/eMELA-config #" $MG5_DIR/input/mg5_configuration.txt

# Install HepMC2.
RUN echo "install hepmc" | XDG_CONFIG_HOME="$MG5_DIR/input" MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^hepmc_path = $HEPTOOLS_DIR/hepmc #" $MG5_DIR/input/mg5_configuration.txt

# Install Pythia8.
RUN echo "install pythia8" | XDG_CONFIG_HOME="$MG5_DIR/input" MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^pythia8_path = $HEPTOOLS_DIR/pythia8 #" $MG5_DIR/input/mg5_configuration.txt \
    && grep -q "^mg5amc_py8_interface_path = $HEPTOOLS_DIR/MG5aMC_PY8_interface #" $MG5_DIR/input/mg5_configuration.txt

# Install MadAnalysis5. This step also installs FastJet.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/madanalysis5/log-open-failure,target=/tmp/patches1,readonly \
    --mount=type=bind,source=patches/madanalysis5/read-only-environment-support,target=/tmp/patches2,readonly \
    --mount=type=bind,source=scripts/fix-ma5-version.py,target=/tmp/fix-ma5-version.py,readonly \
    echo "install MadAnalysis5" | XDG_CONFIG_HOME="$MG5_DIR/input" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^madanalysis5_path = $MA5_DIR #" $MG5_DIR/input/mg5_configuration.txt \
    && test -s $MA5_DIR/tools/fastjet/bin/fastjet-config \
    && /tmp/apply-patches.sh /tmp/patches1 $MA5_DIR \
    && /tmp/apply-patches.sh /tmp/patches2 $MA5_DIR \
    && /tmp/fix-ma5-version.py $MA5_DIR

# Install Delphes.
RUN echo "install delphes" | $MA5_DIR/bin/ma5 -f \
    && echo "set delphes_path $MA5_DIR/tools/delphes" | $MG5_DIR/bin/mg5_aMC

# Set environment variables.
ENV DELPHES_HOME=$MA5_DIR/tools/delphes
ENV MA5_BASE=$MA5_DIR
ENV PATH="$MG5_DIR/bin:$HEPTOOLS_DIR/bin:$MA5_DIR/bin:$MA5_DIR/tools/fastjet/bin:$MA5_DIR/tools/delphes:$MA5_DIR/tools/SampleAnalyzer/ExternalSymLink/Bin:$PATH"
ENV LIBRARY_PATH="$HEPTOOLS_DIR/lhapdf6_py3/lib:$MA5_DIR/tools/fastjet/lib:$MA5_DIR/tools/delphes:$LIBRARY_PATH"
ENV LD_LIBRARY_PATH="$HEPTOOLS_DIR/lhapdf6_py3/lib:$MA5_DIR/tools/fastjet/lib:$MA5_DIR/tools/delphes:$MA5_DIR/tools/SampleAnalyzer/Lib:$MA5_DIR/tools/SampleAnalyzer/ExternalSymLink/Lib:$LD_LIBRARY_PATH"
ENV PYTHONPATH="$HEPTOOLS_DIR/lhapdf6_py3/lib/python3.12/dist-packages:$MA5_DIR/tools/delphes/python:$PYTHONPATH"
ENV CPLUS_INCLUDE_PATH="$MA5_DIR/tools/fastjet/include:$CPLUS_INCLUDE_PATH"
ENV ROOT_INCLUDE_PATH="$MA5_DIR/tools/delphes/external:$ROOT_INCLUDE_PATH"

# Rebuild the SampleAnalyzer static library for MadAnalysis 5.
RUN $MA5_DIR/bin/ma5 -bf \
    && rm $MA5_DIR/.ma5history \
    && touch $DATA_DIR/.ma5history \
    && ln -s $DATA_DIR/.ma5history $MA5_DIR/.ma5history

WORKDIR /work
CMD ["/bin/bash"]
