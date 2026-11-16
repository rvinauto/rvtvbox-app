#!/usr/bin/env bash
# 把上游 fish2018/webhtv 的修复打到 Silent1566/webhtv 主线，并编译校验两个 ABI。
# 用法: bash apply.sh [fork 克隆目录]
set -euo pipefail

FORK_URL="${FORK_URL:-https://github.com/Silent1566/webhtv.git}"
FORK_REF="${FORK_REF:-852d8428d3ea207c86bc1ce18c999ffce8df67ee}"   # release/v5.6.0-beta-202611080849
WORK="${1:-$PWD/webhtv-fork}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"   # webhtv/ 根，patches 在其下

echo "== 1/4 取 fork 源码 @ $FORK_REF"
if [ ! -d "$WORK/.git" ]; then
  git init -q "$WORK"
  git -C "$WORK" remote add origin "$FORK_URL"
fi
if ! git -C "$WORK" fetch -q --depth 1 origin "$FORK_REF"; then
  git -C "$WORK" fetch -q origin "$FORK_REF"
fi
git -C "$WORK" checkout -q --detach FETCH_HEAD
cd "$WORK"

echo "== 2/4 打补丁（已解冲突版）"
git config user.email "ci@local"; git config user.name "ci"
# 合并补丁是普通 diff（非 mailbox），用 git apply -3
git apply -3 --whitespace=nowarn "$DIR/patches/merged-all-3-upstream-fixes.patch"
git add -A
git commit -q -m "feat: absorb upstream fish2018/webhtv fixes (pan proxy lifecycle, ARMv7 libass, live inset)"

echo "== 3/4 SDK 定位"
if [ ! -f local.properties ]; then
  [ -n "${ANDROID_HOME:-}" ] && echo "sdk.dir=$ANDROID_HOME" > local.properties
fi


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

echo "== 4/4 编译两个 ABI"
chmod +x gradlew
./gradlew :app:compileMobileArm64_v8aReleaseJavaWithJavac \
          :app:compileArmeabi_v7aReleaseJavaWithJavac ${GRADLE_ARGS[@]+"${GRADLE_ARGS[@]}"} --no-daemon

echo "== 双 ABI native 校验"
python3 scripts/test_verify_exo_ass.py

echo "OK: 上游修复已落地并通过双 ABI 编译校验"
