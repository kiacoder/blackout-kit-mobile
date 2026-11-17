#!/usr/bin/env python3
"""Adapt a disposable copy of the pinned official JNI bridge for app ownership.
No logcat/profile dumps or filesystem UAPI server. JNI is the sole control path.
Called only after the build script checks the official source revision/diff.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])
p = root / 'api-android.go'
s = p.read_text()
for item in ['"fmt"', '"net"', '"os"', '"os/signal"', '"runtime"', '"unsafe"', '"golang.org/x/sys/unix"']:
    s = s.replace('\t' + item + '\n', '')
s = '\n'.join(line for line in s.split('\n') if not line.strip().endswith('/ipc"'))
a = s.index('type AndroidLogger struct {')
b = s.index('type TunnelHandle struct {', a)
s = s[:a] + s[b:]
s = s.replace('\tuapi   net.Listener\n', '')
s = s.replace('"math"', '"math"\n\t"sync"')
s = s.replace('var tunnelHandles map[int32]TunnelHandle', 'var tunnelHandles map[int32]TunnelHandle\nvar tunnelHandlesMu sync.Mutex')
# Serialize all handle operations; Kotlin caller ordering alone is insufficient.
import re
s = re.sub(r'(func (?:awg|wg)(?:TurnOn|TurnOff|GetSocketV4|GetSocketV6|GetConfig)\([^\n]*\{)',
           r'\1\n\ttunnelHandlesMu.Lock()\n\tdefer tunnelHandlesMu.Unlock()', s)
a = s.index('func init() {')
b = s.index('\n//export ', a)
s = s[:a] + 'func init() { tunnelHandles = make(map[int32]TunnelHandle) }\n' + s[b:]
a = s.index('\ttag := cstring(')
b = s.index('\n\ttun, name, err :=', a)
s = s[:a] + '\tlogger := device.NewLogger(device.LogLevelSilent, "")\n' + s[b:]
# The matching core patch consumes fd on ALL return paths. Never raw-close
# after os.NewFile has installed a finalizer: a reused fd could be closed later.
fd_failure = '\ttun, name, err := tun.CreateUnmonitoredTUNFromFD(int(tunFd))\n\tif err != nil {\n\t\tunix.Close(int(tunFd))'
assert fd_failure in s
s = s.replace(fd_failure, '\ttun, name, err := tun.CreateUnmonitoredTUNFromFD(int(tunFd))\n\tif err != nil {')
old = '\terr = device.IpcSet(settings)\n\tif err != nil {\n\t\tunix.Close(int(tunFd))'
assert old in s
s = s.replace(old, '\terr = device.IpcSet(settings)\n\tif err != nil {\n\t\tdevice.Close()')
a = s.index('\tvar uapi net.Listener')
b = s.index('\terr = device.Up()', a)
s = s[:a] + s[b:]
s = s.replace('\t\tuapiFile.Close()\n', '')
s = s.replace('TunnelHandle{device: device, uapi: uapi}', 'TunnelHandle{device: device}')
s = s.replace('\tif handle.uapi != nil {\n\t\thandle.uapi.Close()\n\t}\n', '')
assert 'uapiFile' not in s and 'net.Listener' not in s and 'handle.uapi' not in s
prefix = 'awg' if '//export awgTurnOn' in s else 'wg'
# Secret-free lifecycle status; never export IpcGet output to the app for polling.
s += f'''
//export {prefix}IsClosed
func {prefix}IsClosed(tunnelHandle int32) int32 {{
    tunnelHandlesMu.Lock()
    defer tunnelHandlesMu.Unlock()
    handle, ok := tunnelHandles[tunnelHandle]
    if !ok {{ return 1 }}
    select {{
    case <-handle.device.Wait(): return 1
    default: return 0
    }}
}}
'''
p.write_text(s)
p = root / 'jni.c'
s = p.read_text().replace('#include <string.h>', '#include <string.h>\n#include <unistd.h>')
s = s.replace('const char *ifname_str = (*env)->GetStringUTFChars(env, ifname, 0);',
              'const char *ifname_str = (*env)->GetStringUTFChars(env, ifname, 0);\n\tif (!ifname_str) { close(tun_fd); return -1; }')
s = s.replace('const char *settings_str = (*env)->GetStringUTFChars(env, settings, 0);',
              'const char *settings_str = (*env)->GetStringUTFChars(env, settings, 0);\n\tif (!settings_str) { (*env)->ReleaseStringUTFChars(env, ifname, ifname_str); close(tun_fd); return -1; }')
p.write_text(s)
java_prefix = 'Java_org_amnezia_awg_GoBackend_' if prefix == 'awg' else 'Java_com_wireguard_android_backend_GoBackend_'
s += f'''
extern int {prefix}IsClosed(int handle);
JNIEXPORT jint JNICALL {java_prefix}{prefix}IsClosed(JNIEnv *env, jclass c, jint handle)
{{
    return {prefix}IsClosed(handle);
}}
'''
p.write_text(s)
