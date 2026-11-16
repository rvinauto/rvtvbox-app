#!/usr/bin/env bash
# 出「已吸收上游修复」的 WebHTV APK：fork Silent1566/webhtv + 3 个上游补丁。
# 这是唯一会产出「改进版」APK 的脚本 —— XingChen 那条线是原版星辰，与本仓库无关。
set -euo pipefail

FORK_URL="${FORK_URL:-https://github.com/Silent1566/webhtv.git}"
FORK_REF="${FORK_REF:-852d8428d3ea207c86bc1ce18c999ffce8df67ee}"
WORK="${1:-$PWD/webhtv-fork}"
TASK="${TASK:-:app:assembleMobileArm64_v8aRelease}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"   # webhtv/ 根，patches 在其下

echo "== 1/5 取 fork 源码 @ $FORK_REF"
if [ ! -d "$WORK/.git" ]; then
  git init -q "$WORK"
  git -C "$WORK" remote add origin "$FORK_URL"
fi
if ! git -C "$WORK" fetch -q --depth 1 origin "$FORK_REF"; then
  git -C "$WORK" fetch -q origin "$FORK_REF"
fi
git -C "$WORK" checkout -q --detach FETCH_HEAD
cd "$WORK"

echo "== 2/5 打上游修复补丁"
git config user.email "ci@local"; git config user.name "ci"
git apply -3 --whitespace=nowarn "$DIR/patches/merged-all-3-upstream-fixes.patch"
git add -A
git commit -q -m "feat: absorb upstream fish2018/webhtv fixes (pan proxy lifecycle, ARMv7 libass, live inset)"

echo "== 3/5 临时签名 + local.properties"
KS="${RUNNER_TEMP:-/tmp}/webhtv.p12"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -storetype PKCS12 -alias webhtv \
    -keyalg RSA -keysize 2048 -validity 3650 \
    -storepass webhtv -keypass webhtv -dname "CN=WebHTV-CI" >/dev/null 2>&1
fi
: > local.properties
[ -n "${ANDROID_HOME:-}" ] && echo "sdk.dir=$ANDROID_HOME" >> local.properties
{
  echo "storeFile=$KS"
  echo "keyAlias=webhtv"
  echo "storePassword=webhtv"
  echo "keyPassword=webhtv"
} >> local.properties


echo "== 定位 Python 3.10（Chaquopy 强制要求）"
PY310="$(command -v python3.10 || true)"
if [ -z "$PY310" ]; then
  PY310="$(python3 -c 'import sys; print(sys.executable) if sys.version_info[:2]==(3,10) else ""' 2>/dev/null || true)"
fi
if [ -z "$PY310" ]; then
  echo "[warn] 未找到 Python 3.10，Chaquopy 可能报 'Couldn't find Python 3.10'"; PY310=""
else
  echo "buildPython=$PY310"
fi
GRADLE_ARGS=()
if [ -n "$PY310" ]; then GRADLE_ARGS+=("-PchaquopyBuildPython=$PY310"); fi

echo "== 4/5 构建 $TASK"
chmod +x gradlew
./gradlew "$TASK" ${GRADLE_ARGS[@]+"${GRADLE_ARGS[@]}"} --no-daemon

echo "== 5/5 产物"
find app/build/outputs/apk -name '*.apk' -exec ls -lh {} \;
