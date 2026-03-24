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
# Regenerating Autotools files for hepmc requires: automake, libtool
# Building pythia8 requires: rsync
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    automake=1:1.16.* \
    ghostscript=9.55.* \
    gnuplot-nox=5.4.* \
    libtool=2.4.* \
    python3-lxml=4.8.* \
    python3-matplotlib=3.5.* \
    python3-pip=22.0.* \
    python3-requests=2.25.* \
    python3-scipy=1.8.* \
    python3-semantic-version=2.8.* \
    python3-six=1.16.* \
    rsync=3.2.* \
    vim=2:8.2.* \
    && rm -rf /var/lib/apt/lists/*

# MadAnalysis5 dependencies.
RUN wget -nv https://raw.githubusercontent.com/MadAnalysis/madanalysis5/refs/heads/main/requirements.txt \
    && pip install --no-cache-dir -r requirements.txt \
    && rm -f requirements.txt

ARG MG5_URL=https://launchpad.net/mg5amcnlo/3.0/3.6.x/+download/MG5_aMC_v3.7.0.tar.gz
ARG MG5_SHA256=b151dee0a46bfd625959ca0202aa5f3a26ed5492a0fb98e1f3c164c860947870

ENV MG5_NO_REFRESH_HEPTOOLS_INSTALLERS=1
ENV MA5_NO_AUTOREBUILD=1

RUN mkdir /data

# Install MadGraph5_aMC@NLO.
# A patch is needed in the MadGraph5_aMC@NLO codebase to support
# MG5_NO_REFRESH_HEPTOOLS_INSTALLERS.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/mg5amcnlo/allow-skipping-heptools-installers-refresh,target=/tmp/patches,readonly \
    wget -nv -O mg5.tar.gz "$MG5_URL" \
    && echo "$MG5_SHA256  mg5.tar.gz" | sha256sum -c - \
    && tar -xzf mg5.tar.gz \
    && rm -f mg5.tar.gz \
    && mv MG5_* MG5_aMC \
    && /tmp/apply-patches.sh /tmp/patches /opt/MG5_aMC \
    && mv /opt/MG5_aMC/models /data \
    && ln -s /data/models /opt/MG5_aMC/models

# Disable automatic updates.
RUN echo "n" | /opt/MG5_aMC/bin/mg5_aMC \
    && echo "set auto_update 0" | /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^auto_update = 0" /opt/MG5_aMC/input/mg5_configuration.txt

# Install LHAPDF6.
# Note that this step downloads HEPToolsInstallers.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/lhapdf/migrate-to-requiring-py3,target=/tmp/patches,readonly \
    echo "install lhapdf6" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && /tmp/apply-patches.sh /tmp/patches /opt/MG5_aMC/HEPTools/lhapdf6_py3 \
    && grep -q "^lhapdf_py3 =" /opt/MG5_aMC/input/mg5_configuration.txt \
    && mv /opt/MG5_aMC/HEPTools/lhapdf6_py3/share/LHAPDF /data \
    && ln -s /data/LHAPDF /opt/MG5_aMC/HEPTools/lhapdf6_py3/share/LHAPDF

# Install HepMC2.
# We need to apply a patch to the HEPToolsInstallers directory
# to update HepMC2's config.guess file.
# See also: https://answers.launchpad.net/mg5amcnlo/+question/706536
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/HEPToolsInstallers/update-hepmc-config-guess,target=/tmp/patches,readonly \
    /tmp/apply-patches.sh /tmp/patches /opt/MG5_aMC/HEPTools/HEPToolsInstallers \
    && echo "install hepmc" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^hepmc_path =" /opt/MG5_aMC/input/mg5_configuration.txt

# Install Pythia8.
RUN echo "install pythia8" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^lhapdf_py3 =" /opt/MG5_aMC/input/mg5_configuration.txt \
    && grep -q "^pythia8_path =" /opt/MG5_aMC/input/mg5_configuration.txt \
    && grep -q "^mg5amc_py8_interface_path =" /opt/MG5_aMC/input/mg5_configuration.txt

# Install FastJet.
RUN echo "install fastjet" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^fastjet =" /opt/MG5_aMC/input/mg5_configuration.txt

# Install Delphes.
RUN echo "install Delphes" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && test -s /opt/MG5_aMC/Delphes/DelphesSTDHEP

# Install MadAnalysis5.
RUN echo "install MadAnalysis5" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^madanalysis5_path =" /opt/MG5_aMC/input/mg5_configuration.txt

# Enable automatic Python2 -> Python3 model conversion.
RUN echo "set auto_convert_model T" | /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^auto_convert_model = True" /opt/MG5_aMC/input/mg5_configuration.txt

# Set environment variables.
ENV PATH="/opt/MG5_aMC/bin:/opt/MG5_aMC/HEPTools/bin:/opt/MG5_aMC/Delphes:/opt/MG5_aMC/HEPTools/madanalysis5/madanalysis5/bin:$PATH"
ENV LIBRARY_PATH="/opt/MG5_aMC/HEPTools/lhapdf6_py3/lib:/opt/MG5_aMC/Delphes:$LIBRARY_PATH"
ENV LD_LIBRARY_PATH="/opt/MG5_aMC/HEPTools/lhapdf6_py3/lib:/opt/MG5_aMC/Delphes:$LD_LIBRARY_PATH"
ENV CPLUS_INCLUDE_PATH="/opt/MG5_aMC/HEPTools/lhapdf6_py3/include:/opt/MG5_aMC/Delphes:$CPLUS_INCLUDE_PATH"
ENV PYTHONPATH="/opt/MG5_aMC/HEPTools/lhapdf6_py3/lib/python3.10/dist-packages:$PYTHONPATH"

# Build the SampleAnalyzer static library for MadAnalysis 5.
# This step must be performed after setting the path-related environment variables.
# We also need to apply patches to:
# - Prevent writing to the installation directory during configuration checks.
# - Skip rebuilding when MA5_NO_AUTOREBUILD is set.
RUN --mount=type=bind,source=scripts/apply-patches.sh,target=/tmp/apply-patches.sh,readonly \
    --mount=type=bind,source=patches/madanalysis5/read-only-environment-support,target=/tmp/patches1,readonly \
    --mount=type=bind,source=patches/madanalysis5/log-open-failure,target=/tmp/patches2,readonly \
    /tmp/apply-patches.sh /tmp/patches1 /opt/MG5_aMC/HEPTools/madanalysis5/madanalysis5 \
    && /tmp/apply-patches.sh /tmp/patches2 /opt/MG5_aMC/HEPTools/madanalysis5/madanalysis5 \
    && MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/HEPTools/madanalysis5/madanalysis5/bin/ma5 -bf

WORKDIR /work
CMD ["/bin/bash"]
