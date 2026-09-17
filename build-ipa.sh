#!/bin/bash
# ============================================================
# Beans Music IPA 构建脚本（需 macOS + Xcode）
# 用法: ./build-ipa.sh [signed|unsigned]
#   unsigned: 构建无签名 IPA（侧载/测试）
#   signed:   构建带签名 IPA（需要开发者证书与描述文件）
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-unsigned}"
VER="1.6.5.1"

echo "==> 检查 xcodegen ..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未安装 xcodegen，正在安装..."
  brew install xcodegen
fi

echo "==> 生成 Xcode 工程 ..."
xcodegen generate

echo "==> 构建（$MODE）..."
rm -rf build Payload
if [ "$MODE" = "signed" ]; then
  xcodebuild \
    -project Beans.xcodeproj \
    -scheme Beans \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath build \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build
else
  xcodebuild \
    -project Beans.xcodeproj \
    -scheme Beans \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build
fi

echo "==> 打包 IPA ..."
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Beans.app Payload/
if [ "$MODE" = "signed" ]; then
  ditto -c -k --sequesterRsrc --keepParent Payload Beans-${VER}-signed.ipa
  echo "✅ 已生成: Beans-${VER}-signed.ipa"
else
  ditto -c -k --sequesterRsrc --keepParent Payload Beans-${VER}-unsigned.ipa
  echo "✅ 已生成: Beans-${VER}-unsigned.ipa（未签名，可在测试设备侧载或自行重签名）"
fi
rm -rf Payload
