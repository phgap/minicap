#!/usr/bin/env bash

# Fail on error, verbose output
set -exo pipefail

# Clean up
cleanup() {
  # echo "=============== Clean up ==============="
  adb -s "$serial_no" forward --remove tcp:"$port"
  adb -s "$serial_no" shell rm -r $dir
}

trap cleanup EXIT ERR
# Build project
experimental/gradlew -p experimental assembleDebug
ndk-build NDK_DEBUG=1 1>&2

if [ $# -lt 1 ]; then
  echo "Error: argument 1 should be serial no"
  exit 1
fi
serial_no=$1

# Figure out which ABI and SDK the device has
abi=$(adb -s "$serial_no" shell getprop ro.product.cpu.abi | tr -d '\r')
sdk=$(adb -s "$serial_no" shell getprop ro.build.version.sdk | tr -d '\r')
pre=$(adb -s "$serial_no" shell getprop ro.build.version.preview_sdk | tr -d '\r')
rel=$(adb -s "$serial_no" shell getprop ro.build.version.release | tr -d '\r')

if [[ -n "$pre" && "$pre" > "0" ]]; then
  sdk=$(($sdk + 1))
fi

# PIE is only supported since SDK 16
if (($sdk >= 16)); then
  bin=minicap
else
  bin=minicap-nopie
fi

apk="app_process /system/bin io.devicefarmer.minicap.Main"


rotate=0
# 判断是否有至少两个参数传入
if [ $# -ge 2 ]; then
  rotate=$2
else
  rotate=0
fi

echo "rotate is set to $rotate"

args=
set +o pipefail
size=$(adb -s "$serial_no" shell dumpsys window | grep -Eo 'init=[0-9]+x[0-9]+' | head -1 | cut -d= -f 2)
if [ "$size" = "" ]; then
  w=$(adb -s "$serial_no" shell dumpsys window | grep -Eo 'DisplayWidth=[0-9]+' | head -1 | cut -d= -f 2)
  h=$(adb -s "$serial_no" shell dumpsys window | grep -Eo 'DisplayHeight=[0-9]+' | head -1 | cut -d= -f 2)
  size="${w}x${h}"
fi
args="-P $size@$size/${rotate}"
set -o pipefail
shift


# Create a directory for our resources
dir=/data/local/tmp/minicap-devel
# Keep compatible with older devices that don't have `mkdir -p`.
adb -s "$serial_no" shell "mkdir $dir 2>/dev/null || true"

# Upload the binary
adb -s "$serial_no" push libs/$abi/$bin $dir

port=1313
if [ $# -ge 3 ]; then
  port=$3
else
  port=1313
fi

adb -s "$serial_no" forward tcp:"$port" localabstract:minicap
# Upload the shared library
if [ -e jni/minicap-shared/aosp/libs/android-$rel/$abi/minicap.so ]; then
  adb -s "$serial_no" push jni/minicap-shared/aosp/libs/android-$rel/$abi/minicap.so $dir
  adb -s "$serial_no" shell LD_LIBRARY_PATH=$dir $dir/$bin $args
else
  if [ -e jni/minicap-shared/aosp/libs/android-$sdk/$abi/minicap.so ]; then
    adb -s "$serial_no" push jni/minicap-shared/aosp/libs/android-$sdk/$abi/minicap.so $dir
    adb -s "$serial_no" shell LD_LIBRARY_PATH=$dir $dir/$bin $args
  else
    adb -s "$serial_no" push experimental/app/build/outputs/apk/debug/minicap-debug.apk $dir
    adb -s "$serial_no" shell CLASSPATH=$dir/minicap-debug.apk $apk $args
  fi
fi


