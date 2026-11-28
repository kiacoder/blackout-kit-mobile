"""Pinned, emulator-only Mihomo direct TUN experiment.

Android VpnService has already selected the app UIDs and installed routes.
Never ask a sandboxed Android app to read /data/system/packages.xml.
Refuse native UID/package/automatic route controls on inherited descriptors.
"""
import argparse
import hashlib
import json
from pathlib import Path

FILES = {
    "listener/sing_tun/server_android.go": (
        "758f149f0c296d9f2d3acbb2559f00e078bc7b019dfccc03be14a709e6ecc7c9",
        "func (l *Listener) buildAndroidRules(tunOptions *tun.Options) error {\n",
        """func (l *Listener) buildAndroidRules(tunOptions *tun.Options) error {
    if tunOptions.FileDescriptor > 0 {
        if tunOptions.AutoRoute || l.options.AutoDetectInterface ||
            len(tunOptions.IncludeAndroidUser) != 0 ||
            len(tunOptions.IncludePackage) != 0 || len(tunOptions.ExcludePackage) != 0 ||
            len(tunOptions.IncludeUID) != 0 || len(tunOptions.ExcludeUID) != 0 {
            return errors.New("inherited TUN requires Android-managed routes and app selection")
        }
        return nil
    }
""",
    ),
    "listener/listener.go": (
        "1a11cda3fb4a87875d817fe29f1e79973cb8cb6eeccc0ae5e22db15df1277758",
        'log.Errorln("Start TUN listening error: %s", err.Error())',
        '''if tunConf.FileDescriptor > 0 {
                // No successful startup when the inherited TUN failed.
                log.Fatalln("Inherited TUN initialization failed")
            }
            log.Errorln("Start TUN listening error: %s", err.Error())''',
    ),
}


def prepare(source: Path, output: Path) -> Path:
    source, output = source.resolve(), output.resolve()
    replacement = {}
    for relative, (pin, anchor, patch) in FILES.items():
        original = source / relative
        data = original.read_bytes().replace(b"\r\n", b"\n")
        if hashlib.sha256(data).hexdigest() != pin:
            raise ValueError(f"Unreviewed Mihomo input: {relative}")
        content = data.decode()
        if content.count(anchor) != 1:
            raise ValueError(f"Unexpected layout: {relative}")
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        content = content.replace(anchor, patch, 1)
        if relative == "listener/listener.go":
            imports = '\t"net"\n'
            ready = '\ttunLister = lister\n'
            if content.count(imports) != 1 or content.count(ready) != 1:
                raise ValueError("Unexpected direct readiness layout")
            content = content.replace(imports, imports + '\t"os"\n', 1)
            content = content.replace(ready, ready + """	if tunConf.FileDescriptor > 0 {
        // The parent owns a unique private config path for this session.
        // Publish readiness only after sing_tun.New has started its stack.
        marker, markerErr := os.OpenFile(C.Path.Config()+".tun-ready", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
        if markerErr != nil {
            log.Fatalln("Inherited TUN readiness publication failed")
        }
        _, writeErr := marker.WriteString("ready\\n")
        closeErr := marker.Close()
        if writeErr != nil || closeErr != nil {
            log.Fatalln("Inherited TUN readiness publication failed")
        }
    }
""", 1)
        target.write_bytes(content.encode())
        replacement[str(original)] = str(target)
    manifest = output / "overlay.json"
    manifest.write_text(json.dumps({"Replace": replacement}, indent=2), encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(prepare(args.source, args.output))
