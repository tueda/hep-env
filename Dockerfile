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

# Install MadGraph5_aMC@NLO.
RUN wget -nv -O mg5.tar.gz "$MG5_URL" \
    && echo "$MG5_SHA256  mg5.tar.gz" | sha256sum -c - \
    && tar -xzf mg5.tar.gz \
    && rm -f mg5.tar.gz \
    && mv MG5_* MG5_aMC

# Disable automatic updates.
RUN echo "n" | /opt/MG5_aMC/bin/mg5_aMC \
    && echo "set auto_update 0" | /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^auto_update = 0" /opt/MG5_aMC/input/mg5_configuration.txt

# Install HepMC2.
# We need to use a patched version of the HEPToolsInstallers repository
# to regenerate Autotools files for HepMC2.
# See also: https://answers.launchpad.net/mg5amcnlo/+question/706536
RUN git clone https://github.com/tueda/HEPToolsInstallers.git -b fix/hepmc2-always-autoreconf \
    && echo "install hepmc --local" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^hepmc_path =" /opt/MG5_aMC/input/mg5_configuration.txt \
    && rm -rf HEPToolsInstallers

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
    && grep -q "^madanalysis5_path =" /opt/MG5_aMC/input/mg5_configuration.txt \
    && echo "exit" | MAKEFLAGS="-j$(nproc)" /opt/MG5_aMC/HEPTools/madanalysis5/madanalysis5/bin/ma5 -f

# Enable automatic Python2 -> Python3 model conversion.
RUN echo "set auto_convert_model T" | /opt/MG5_aMC/bin/mg5_aMC \
    && grep -q "^auto_convert_model = True" /opt/MG5_aMC/input/mg5_configuration.txt

ENV PATH="/opt/MG5_aMC/bin:/opt/MG5_aMC/HEPTools/bin:/opt/MG5_aMC/HEPTools/madanalysis5/madanalysis5/bin:$PATH"
WORKDIR /work
CMD ["/bin/bash"]
