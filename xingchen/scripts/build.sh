#!/usr/bin/env bash
# 在 x86_64 CI/本机上拉取 XingChen 源码并出 arm64 APK。
# 不需要 qemu、不需要 arm64 宿主：这是官方 CI 的同款路径。
set -euo pipefail

SRC_URL="${SRC_URL:-https://github.com/XingChenApp/xingchen.git}"
SRC_REF="${SRC_REF:-52450c0461659685425bd7f3deacd2e899d13a49}"
WORK="${WORK:-$PWD/xingchen-src}"
TASK="${TASK:-:app:assembleMobileArm64_v8aRelease}"

echo "== 1/4 取源码 $SRC_REF"
if [ ! -d "$WORK/.git" ]; then
  git init -q "$WORK"
  git -C "$WORK" remote add origin "$SRC_URL"
fi
if ! git -C "$WORK" fetch -q --depth 1 origin "$SRC_REF"; then
  git -C "$WORK" fetch -q origin "$SRC_REF"
fi
git -C "$WORK" checkout -q --detach FETCH_HEAD
cd "$WORK"

echo "== 2/4 下载两个外部件（失败降级，不阻塞）"
TARGET=third_party/mihomo/prebuilt/arm64-v8a/libmihomo.so
mkdir -p "$(dirname "$TARGET")"
if [ ! -s "$TARGET" ]; then
  if curl -fL --retry 3 -o /tmp/mihomo.gz \
      "https://xingchen-dl.pages.dev/clash/mihomo-android-arm64-v8-v1.19.33.gz"; then
    gzip -dc /tmp/mihomo.gz > "$TARGET.tmp"
    if echo "cfa0be78846bfef7272fe5a73089f8cf0e1f15a6ffb601f5cc809f457f712f67  $TARGET.tmp" | sha256sum -c -; then
      mv "$TARGET.tmp" "$TARGET"; ls -lh "$TARGET"
    else
      echo "[warn] mihomo sha256 不匹配，丢弃（Clash 节点功能不可用）"; rm -f "$TARGET.tmp"
    fi
  else
    echo "[warn] mihomo 下载失败（Clash 节点功能不可用）"
  fi
fi

mkdir -p app/libs-compile
if [ ! -s app/libs-compile/sherpa-onnx.aar ]; then
  if curl -fsSL --retry 2 -o app/libs-compile/sherpa-onnx.aar \
      "https://raw.githubusercontent.com/XingChenApp/xingchen-asr/main/sherpa-onnx.aar"; then
    ls -lh app/libs-compile/sherpa-onnx.aar
  else
    echo "[warn] sherpa-onnx.aar 下载失败，注释掉 compileOnly"
    rm -f app/libs-compile/sherpa-onnx.aar
    sed -i 's#^\(.*\)compileOnly files("libs-compile/sherpa-onnx.aar")#\1//compileOnly files("libs-compile/sherpa-onnx.aar")#' app/build.gradle
  fi
fi

echo "== 3/4 生成临时签名 + local.properties"
if [ ! -f local.properties ] || ! grep -q storeFile local.properties; then
  KS="${RUNNER_TEMP:-/tmp}/xingchen.p12"
  rm -f "$KS"
  keytool -genkeypair -v -keystore "$KS" -storetype PKCS12 -alias xingchen \
    -keyalg RSA -keysize 2048 -validity 3650 \
    -storepass xingchen -keypass xingchen -dname "CN=XingChen" >/dev/null 2>&1
  {
    echo "storeFile=$KS"
    echo "keyAlias=xingchen"
    echo "storePassword=xingchen"
    echo "keyPassword=xingchen"
    [ -n "${ANDROID_HOME:-}" ] && echo "sdk.dir=$ANDROID_HOME"
  } >> local.properties
fi

echo "== 4/4 构建 $TASK"
chmod +x gradlew
./gradlew "$TASK" --no-daemon

echo "== 产物"
find app/build/outputs/apk -name '*.apk' -exec ls -lh {} \;
