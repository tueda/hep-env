# NOTE: We currently use Ubuntu 22.04 rather than 24.04 because Ubuntu 24.04
# ships Python 3.12, which triggers the MadGraph warning:
# "WARNING:root:python3.12+ support: For reweighting feature, please use 3.6.X release."
# See also: https://answers.launchpad.net/mg5amcnlo/+question/816178
FROM hepdock/root:6.34.02-ubuntu22.04

LABEL org.opencontainers.image.source="https://github.com/tueda/hep-env"
LABEL org.opencontainers.image.description="Container image for high-energy physics tools"
LABEL org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /opt
ENV LANG=C.UTF-8

# Running mg5_aMC requires: python3-six
# Building pythia8 requires: rsync
# Building Delphes (from MadAnalysis5) requires: tcl
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ghostscript=9.55.* \
    gnuplot-nox=5.4.* \
    libboost-all-dev=1.74.* \
    python3-lxml=4.8.* \
    python3-matplotlib=3.5.* \
    python3-pip=22.0.* \
    python3-requests=2.25.* \
    python3-scipy=1.8.* \
    python3-semantic-version=2.8.* \
    python3-six=1.16.* \
    rsync=3.2.* \
    tcl=8.6.* \
    vim=2:8.2.* \
    && rm -rf /var/lib/apt/lists/*

# MadAnalysis5 dependencies.
RUN wget -nv https://raw.githubusercontent.com/MadAnalysis/madanalysis5/refs/heads/main/requirements.txt \
    && pip install --no-cache-dir -r requirements.txt \
    && rm -f requirements.txt

ARG MG5_URL=https://launchpad.net/mg5amcnlo/3.0/3.6.x/+download/MG5_aMC_v3.7.0.tar.gz
ARG MG5_SHA256=b151dee0a46bfd625959ca0202aa5f3a26ed5492a0fb98e1f3c164c860947870

ARG MG5_DIR=/opt/MG5_aMC
ARG MA5_DIR=$MG5_DIR/HEPTools/madanalysis5/madanalysis5
ARG DATA_DIR=/data

ENV MG5_NO_REFRESH_HEPTOOLS_INSTALLERS=1
ENV MA5_NO_AUTOREBUILD=1

RUN mkdir $DATA_DIR

# Install MadGraph5_aMC@NLO.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/mg5amcnlo/allow-skipping-heptools-installers-refresh,target=/tmp/patches1,readonly \
    wget -nv -O mg5.tar.gz "$MG5_URL" \
    && echo "$MG5_SHA256  mg5.tar.gz" | sha256sum -c - \
    && tar -xzf mg5.tar.gz \
    && rm -f mg5.tar.gz \
    && mv MG5_* MG5_aMC \
    && /tmp/apply-patches.sh /tmp/patches1 $MG5_DIR \
    && mv $MG5_DIR/models $DATA_DIR \
    && ln -s $DATA_DIR/models $MG5_DIR/models

# Disable automatic updates.
RUN echo "n" | $MG5_DIR/bin/mg5_aMC \
    && echo "set auto_update 0" | $MG5_DIR/bin/mg5_aMC \
    && grep -q "^auto_update = 0" $MG5_DIR/input/mg5_configuration.txt

# Enable automatic Python2 -> Python3 model conversion.
RUN echo "set auto_convert_model T" | $MG5_DIR/bin/mg5_aMC \
    && grep -q "^auto_convert_model = True" $MG5_DIR/input/mg5_configuration.txt

# Install LHAPDF6.
# Note that this step downloads HEPToolsInstallers.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/lhapdf/migrate-to-requiring-py3,target=/tmp/patches1,readonly \
    --mount=type=bind,source=patches/HEPToolsInstallers/update-hepmc-config-guess,target=/tmp/patches2,readonly \
    --mount=type=bind,source=patches/HEPToolsInstallers/install-emela-boost-path,target=/tmp/patches3,readonly \
    echo "install lhapdf6" | MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^lhapdf_py3 =" $MG5_DIR/input/mg5_configuration.txt \
    && /tmp/apply-patches.sh /tmp/patches1 $MG5_DIR/HEPTools/lhapdf6_py3 \
    && /tmp/apply-patches.sh /tmp/patches2 $MG5_DIR/HEPTools/HEPToolsInstallers \
    && /tmp/apply-patches.sh /tmp/patches3 $MG5_DIR/HEPTools/HEPToolsInstallers \
    && mv $MG5_DIR/HEPTools/lhapdf6_py3/share/LHAPDF $DATA_DIR \
    && ln -s $DATA_DIR/LHAPDF $MG5_DIR/HEPTools/lhapdf6_py3/share/LHAPDF

RUN echo "install eMELA" | MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^eMELA = " $MG5_DIR/input/mg5_configuration.txt

# Install HepMC2.
RUN echo "install hepmc" | MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^hepmc_path =" $MG5_DIR/input/mg5_configuration.txt

# Install Pythia8.
RUN echo "install pythia8" | MAKEFLAGS="-j$(nproc)" $MG5_DIR/bin/mg5_aMC \
    && grep -q "^pythia8_path =" $MG5_DIR/input/mg5_configuration.txt \
    && grep -q "^mg5amc_py8_interface_path =" $MG5_DIR/input/mg5_configuration.txt

# Install MadAnalysis5. This step also installs FastJet.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/madanalysis5/read-only-environment-support,target=/tmp/patches1,readonly \
    --mount=type=bind,source=patches/madanalysis5/log-open-failure,target=/tmp/patches2,readonly \
    --mount=type=bind,source=scripts/fix-ma5-version.py,target=/tmp/fix-ma5-version.py,readonly \
    echo "install MadAnalysis5" | $MG5_DIR/bin/mg5_aMC \
    && grep -q "^madanalysis5_path =" $MG5_DIR/input/mg5_configuration.txt \
    && test -s $MA5_DIR/tools/fastjet/bin/fastjet-config \
    && /tmp/apply-patches.sh /tmp/patches1 $MA5_DIR \
    && /tmp/apply-patches.sh /tmp/patches2 $MA5_DIR \
    && /tmp/fix-ma5-version.py $MA5_DIR

# Install Delphes.
RUN echo "install delphes" | $MA5_DIR/bin/ma5 -f \
    && echo "set delphes_path $MA5_DIR/tools/delphes" | $MG5_DIR/bin/mg5_aMC

# Set environment variables.
ENV DELPHES_HOME=$MA5_DIR/tools/delphes
ENV PATH="$MG5_DIR/bin:$MG5_DIR/HEPTools/bin:$MA5_DIR/bin:$MA5_DIR/tools/fastjet/bin:$MA5_DIR/tools/delphes:$PATH"
ENV LIBRARY_PATH="$MG5_DIR/HEPTools/lhapdf6_py3/lib:$MA5_DIR/tools/fastjet/lib:$MA5_DIR/tools/delphes:$LIBRARY_PATH"
ENV LD_LIBRARY_PATH="$MG5_DIR/HEPTools/lhapdf6_py3/lib:$MA5_DIR/tools/fastjet/lib:$MA5_DIR/tools/delphes:$LD_LIBRARY_PATH"
ENV PYTHONPATH="$MG5_DIR/HEPTools/lhapdf6_py3/lib/python3.10/dist-packages:$MA5_DIR/tools/delphes/python:$PYTHONPATH"
ENV CPLUS_INCLUDE_PATH="$MA5_DIR/tools/fastjet/include:$CPLUS_INCLUDE_PATH"

# Rebuild the SampleAnalyzer static library for MadAnalysis 5.
RUN $MA5_DIR/bin/ma5 -bf \
    && rm $MA5_DIR/.ma5history \
    && touch $DATA_DIR/.ma5history \
    && ln -s $DATA_DIR/.ma5history $MA5_DIR/.ma5history

WORKDIR /work
CMD ["/bin/bash"]
