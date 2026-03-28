#!/bin/bash
set -euo pipefail

# No verified prebuilt Java 25 iOS runtime is currently available in-tree or from
# the upstream Pojav runtime workflows. This helper first reuses any locally
# staged archive/runtime, then falls back to building jre25 from source using the
# upstream multiarch scripts with a minimal Java 25 adaptation.

SOURCE_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
DEPENDS_DIR="${SOURCE_DIR}/depends"
RUNTIME_DIR="${DEPENDS_DIR}/java-25-openjdk"
RUNTIME_GLOB="${DEPENDS_DIR}/jre25-*.tar.xz"

if [[ -f "${RUNTIME_DIR}/release" ]]; then
  echo "Java 25 runtime already unpacked at ${RUNTIME_DIR}"
  exit 0
fi

if compgen -G "${RUNTIME_GLOB}" > /dev/null; then
  echo "Java 25 runtime archive already present in ${DEPENDS_DIR}"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Building Java 25 iOS runtime requires macOS."
  exit 1
fi

if [[ -z "${JAVA25_HOME:-}" ]]; then
  JAVA25_HOME="$(/usr/libexec/java_home -v 25 2>/dev/null || true)"
fi

if [[ -z "${JAVA25_HOME}" ]]; then
  echo "Java 25 boot JDK was not found. Set JAVA25_HOME or install JDK 25."
  exit 1
fi

mkdir -p "${DEPENDS_DIR}"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/java25-ios.XXXXXX")"
cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

UPSTREAM_DIR="${TMP_ROOT}/android-openjdk-build-multiarch"
git clone --depth 1 --branch buildjre17-21 \
  https://github.com/PojavLauncherTeam/android-openjdk-build-multiarch \
  "${UPSTREAM_DIR}"

cd "${UPSTREAM_DIR}"
cp -R patches/jre_21 patches/jre_25

cat > 5_clonejdk.sh <<'EOF'
#!/bin/bash
set -e

if [[ -d "openjdk-${TARGET_VERSION}" ]]; then
  exit 0
fi

if [[ "${TARGET_VERSION}" -eq 25 ]]; then
  git clone --depth 1 https://github.com/openjdk/jdk25u openjdk-25
elif [[ "${TARGET_VERSION}" -eq 21 ]]; then
  git clone --branch jdk21.0.1 --depth 1 https://github.com/openjdk/jdk21u openjdk-21
else
  git clone --depth 1 https://github.com/openjdk/jdk17u openjdk-17
fi
EOF
chmod +x 5_clonejdk.sh

python3 - <<'PY'
from pathlib import Path

path = Path("6_buildjdk.sh")
content = path.read_text()
content = content.replace(
    'git apply --reject --whitespace=fix',
    'git apply --3way --reject --whitespace=fix'
)
content = content.replace(
    '--with-boot-jdk=$(/usr/libexec/java_home -v $TARGET_VERSION) \\',
    '--with-boot-jdk=${JAVA25_HOME:-$(/usr/libexec/java_home -v $TARGET_VERSION)} \\'
)
path.write_text(content)
PY

export JAVA25_HOME
export BUILD_IOS=1
export TARGET_VERSION=25
bash ./1_ci_build_arch_aarch64.sh

shopt -s nullglob
archives=(jre25-*.tar.xz)
if [[ ${#archives[@]} -eq 0 ]]; then
  echo "Java 25 runtime build completed without producing jre25 archive."
  exit 1
fi

cp "${archives[@]}" "${DEPENDS_DIR}/"
echo "Stored Java 25 runtime archive in ${DEPENDS_DIR}"
