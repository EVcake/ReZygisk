# shellcheck disable=SC2034
SKIPUNZIP=1

DEBUG=@DEBUG@

if [ "$BOOTMODE" ] && [ "$KSU" ]; then
  ui_print "- Installing from KernelSU app"
  ui_print "- KernelSU version: $KSU_KERNEL_VER_CODE (kernel) + $KSU_VER_CODE (ksud)"
  if [ "$KSU_KERNEL_VER_CODE" ] && [ "$KSU_KERNEL_VER_CODE" -lt 10575 ]; then
    ui_print "*********************************************************"
    ui_print "! KernelSU version is too old!"
    ui_print "! Please update KernelSU to latest version"
    abort    "*********************************************************"
  fi
elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
  ui_print "- Installing from Magisk app"
  if [ "$MAGISK_VER_CODE" -lt 25000 ]; then
    ui_print "*********************************************************"
    ui_print "! Magisk version is too old!"
    ui_print "! Please update Magisk to latest version"
    abort    "*********************************************************"
  fi
else
  ui_print "*********************************************************"
  ui_print "! Install from recovery is not supported"
  ui_print "! Please install from KernelSU or Magisk app"
  abort    "*********************************************************"
fi

VERSION=$(grep_prop version "${TMPDIR}/module.prop")
ui_print "- Installing Zygisksu $VERSION"

# check android
if [ "$API" -lt 29 ]; then
  ui_print "! Unsupported sdk: $API"
  abort "! Minimal supported sdk is 29 (Android 10)"
else
  ui_print "- Device sdk: $API"
fi

# check architecture
if [ "$ARCH" != "arm" ] && [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86" ] && [ "$ARCH" != "x64" ]; then
  abort "! Unsupported platform: $ARCH"
else
  ui_print "- Device platform: $ARCH"
fi

ui_print "- Extracting verify.sh"
unzip -o "$ZIPFILE" 'verify.sh' -d "$TMPDIR" >&2
if [ ! -f "$TMPDIR/verify.sh" ]; then
  ui_print "*********************************************************"
  ui_print "! Unable to extract verify.sh!"
  ui_print "! This zip may be corrupted, please try downloading again"
  abort    "*********************************************************"
fi
. "$TMPDIR/verify.sh"
extract "$ZIPFILE" 'customize.sh'  "$TMPDIR/.vunzip"
extract "$ZIPFILE" 'verify.sh'     "$TMPDIR/.vunzip"
extract "$ZIPFILE" 'sepolicy.rule' "$TMPDIR"

if [ "$KSU" ]; then
  ui_print "- Checking SELinux patches"
  if ! check_sepolicy "$TMPDIR/sepolicy.rule"; then
    ui_print "*********************************************************"
    ui_print "! Unable to apply SELinux patches!"
    ui_print "! Your kernel may not support SELinux patch fully"
    abort    "*********************************************************"
  fi
fi

ui_print "- Extracting module files"
extract "$ZIPFILE" 'daemon.sh'       "$MODPATH"
extract "$ZIPFILE" 'module.prop'     "$MODPATH"
extract "$ZIPFILE" 'post-fs-data.sh' "$MODPATH"
extract "$ZIPFILE" 'service.sh'      "$MODPATH"
if [ "$KSU" ]; then
  extract "$ZIPFILE" 'sepolicy.rule' "$MODPATH"
fi

HAS32BIT=false && [ -d "/system/lib" ] && HAS32BIT=true
HAS64BIT=false && [ -d "/system/lib64" ] && HAS64BIT=true

mkdir "$MODPATH/bin"
mkdir "$MODPATH/system"
[ "$HAS32BIT" = true ] && mkdir "$MODPATH/system/lib"
[ "$HAS64BIT" = true ] && mkdir "$MODPATH/system/lib64"

if [ "$ARCH" = "x86" ] || [ "$ARCH" = "x64" ]; then
  if [ "$HAS32BIT" = true ]; then
    ui_print "- Extracting x86 libraries"
    extract "$ZIPFILE" 'bin/x86/zygiskd' "$MODPATH/bin" true
    mv "$MODPATH/bin/zygiskd" "$MODPATH/bin/zygiskd32"
    extract "$ZIPFILE" 'lib/x86/libinjector.so' "$MODPATH/system/lib" true
    extract "$ZIPFILE" 'lib/x86/libzygiskloader.so' "$MODPATH/system/lib" true
    ln -sf "zygiskd32" "$MODPATH/bin/zygiskwd"
  fi

  if [ "$HAS64BIT" = true ]; then
    ui_print "- Extracting x64 libraries"
    extract "$ZIPFILE" 'bin/x86_64/zygiskd' "$MODPATH/bin" true
    mv "$MODPATH/bin/zygiskd" "$MODPATH/bin/zygiskd64"
    extract "$ZIPFILE" 'lib/x86_64/libinjector.so' "$MODPATH/system/lib64" true
    extract "$ZIPFILE" 'lib/x86_64/libzygiskloader.so' "$MODPATH/system/lib64" true
    ln -sf "zygiskd64" "$MODPATH/bin/zygiskwd"
  fi
else
  if [ "$HAS32BIT" = true ]; then
    ui_print "- Extracting arm libraries"
    extract "$ZIPFILE" 'bin/armeabi-v7a/zygiskd' "$MODPATH/bin" true
    mv "$MODPATH/bin/zygiskd" "$MODPATH/bin/zygiskd32"
    extract "$ZIPFILE" 'lib/armeabi-v7a/libinjector.so' "$MODPATH/system/lib" true
    extract "$ZIPFILE" 'lib/armeabi-v7a/libzygiskloader.so' "$MODPATH/system/lib" true
    ln -sf "zygiskd32" "$MODPATH/bin/zygiskwd"
  fi

  if [ "$HAS64BIT" = true ]; then
    ui_print "- Extracting arm64 libraries"
    extract "$ZIPFILE" 'bin/arm64-v8a/zygiskd' "$MODPATH/bin" true
    mv "$MODPATH/bin/zygiskd" "$MODPATH/bin/zygiskd64"
    extract "$ZIPFILE" 'lib/arm64-v8a/libinjector.so' "$MODPATH/system/lib64" true
    extract "$ZIPFILE" 'lib/arm64-v8a/libzygiskloader.so' "$MODPATH/system/lib64" true
    ln -sf "zygiskd64" "$MODPATH/bin/zygiskwd"
  fi
fi

if [ $DEBUG = false ]; then
  ui_print "- Hex patching"
  SOCKET_PATCH=$(tr -dc 'a-f0-9' </dev/urandom | head -c 18)
  if [ "$HAS32BIT" = true ]; then
    sed -i "s/socket_placeholder/$SOCKET_PATCH/g" "$MODPATH/bin/zygiskd32"
    sed -i "s/socket_placeholder/$SOCKET_PATCH/g" "$MODPATH/system/lib/libinjector.so"
    sed -i "s/socket_placeholder/$SOCKET_PATCH/g" "$MODPATH/system/lib/libzygiskloader.so"
  fi
  if [ "$HAS64BIT" = true ]; then
    sed -i "s/socket_placeholder/$SOCKET_PATCH/g" "$MODPATH/bin/zygiskd64"
    sed -i "s/socket_placeholder/$SOCKET_PATCH/g" "$MODPATH/system/lib64/libinjector.so"
    sed -i "s/socket_placeholder/$SOCKET_PATCH/g" "$MODPATH/system/lib64/libzygiskloader.so"
  fi
fi

ui_print "- Setting permissions"
chmod 0744 "$MODPATH/daemon.sh"
set_perm_recursive "$MODPATH/bin" 0 2000 0755 0755
set_perm_recursive "$MODPATH/system/lib" 0 0 0755 0644 u:object_r:system_lib_file:s0
set_perm_recursive "$MODPATH/system/lib64" 0 0 0755 0644 u:object_r:system_lib_file:s0

# If Huawei's Maple is enabled, system_server is created with a special way which is out of Zygisk's control
HUAWEI_MAPLE_ENABLED=$(grep_prop ro.maple.enable)
if [ "$HUAWEI_MAPLE_ENABLED" == "1" ]; then
  ui_print "- Add ro.maple.enable=0"
  echo "ro.maple.enable=0" >>"$MODPATH/system.prop"
fi
