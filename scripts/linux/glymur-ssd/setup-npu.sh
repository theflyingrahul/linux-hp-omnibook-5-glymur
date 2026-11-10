#!/usr/bin/env bash
set -euo pipefail

# Userspace for the NPU test (issue #20): Ubuntu's FastRPC runtime and
# daemons, plus fastrpc_test and fastrpc-healthcheck built from Qualcomm's
# source (Ubuntu has no package for the tests). Needs the network. Installs
# nothing from hexagon-dsp-binaries-*: those are other boards' DSP files.
#   sudo bash setup-npu.sh
# then: sudo bash check-npu.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
REF=8f59273
SRC="${SRC:-/var/tmp/fastrpc-src}"

apt-get install -y --no-install-recommends fastrpc-support libfastrpc1 libfastrpc-dev \
    git build-essential autoconf automake libtool pkg-config libyaml-dev libbsd-dev

if [ ! -d "$SRC/.git" ]; then
    git clone https://github.com/qualcomm/fastrpc "$SRC"
fi
git -C "$SRC" fetch -q origin "$REF" 2>/dev/null || true
git -C "$SRC" checkout -q "$REF"
cd "$SRC"
[ -f configure ] || bash ./autogen.sh
./configure --prefix=/usr/local
make -j2 -C test
install -m 755 test/fastrpc_test test/fastrpc-healthcheck /usr/local/bin/
command -v fastrpc_test fastrpc-healthcheck

# FastRPC finds the DSP files by the device-tree model name, and its
# healthcheck looks for firmware under /lib/firmware, not .../updates.
install -d /usr/share/qcom/conf.d
cat > /usr/share/qcom/conf.d/hp-omnibook-5-16-bf1xxx.yaml <<'YAML'
machines:
  HP OmniBook 5 Laptop 16-bf1xxx:
    DSP_LIBRARY_PATH: glymur/HP/omnibook-5-16-bf1xxx/dsp
  HP OmniBook 5 Laptop 16-bf1xxx (test):
    DSP_LIBRARY_PATH: glymur/HP/omnibook-5-16-bf1xxx/dsp
  HP OmniBook 5 Laptop 16-bf1xxx (test, A/V):
    DSP_LIBRARY_PATH: glymur/HP/omnibook-5-16-bf1xxx/dsp
YAML
FW=qcom/glymur/HP
[ -e "/lib/firmware/$FW" ] || [ ! -d "/lib/firmware/updates/$FW" ] ||
    ln -s "../../updates/$FW" "/lib/firmware/$FW"
