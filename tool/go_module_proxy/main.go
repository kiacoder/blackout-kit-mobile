// Development-only canonical module ZIP verifier. Uses the Go toolchain's x/mod.
// No hash bypass: both go.mod and module ZIP must match the supplied go.sum.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/mod/module"
	"golang.org/x/mod/sumdb/dirhash"
	modzip "golang.org/x/mod/zip"
)

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func main() {
	if len(os.Args) != 6 {
		panic("usage: verifier source module version go.sum proxy")
	}
	source, path, version, sums, proxy := os.Args[1], os.Args[2], os.Args[3], os.Args[4], os.Args[5]
	expected := map[string]string{}
	f, err := os.Open(sums)
	must(err)
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		fields := strings.Fields(scan.Text())
		if len(fields) == 3 {
			expected[fields[0]+" "+fields[1]] = fields[2]
		}
	}
	must(scan.Err())
	must(f.Close())
	mod, err := os.ReadFile(filepath.Join(source, "go.mod"))
	must(err)
	modHash, err := dirhash.Hash1([]string{"go.mod"}, func(string) (io.ReadCloser, error) { return io.NopCloser(strings.NewReader(string(mod))), nil })
	must(err)
	if modHash != expected[path+" "+version+"/go.mod"] {
		panic("go.mod checksum mismatch or missing pinned sum")
	}
	tmp, err := os.CreateTemp("", "module-*.zip")
	must(err)
	defer os.Remove(tmp.Name())
	must(modzip.CreateFromDir(tmp, module.Version{Path: path, Version: version}, source))
	must(tmp.Close())
	hash, err := dirhash.HashZip(tmp.Name(), dirhash.Hash1)
	must(err)
	if hash != expected[path+" "+version] {
		panic("module ZIP checksum mismatch or missing pinned sum")
	}
	escaped, err := module.EscapePath(path)
	must(err)
	v, err := module.EscapeVersion(version)
	must(err)
	dir := filepath.Join(proxy, escaped, "@v")
	must(os.MkdirAll(dir, 0700))
	zipBytes, err := os.ReadFile(tmp.Name())
	must(err)
	info, err := json.Marshal(map[string]string{"Version": version})
	must(err)
	// Publish metadata last; failed verification never populates the proxy.
	must(os.WriteFile(filepath.Join(dir, v+".zip"), zipBytes, 0600))
	must(os.WriteFile(filepath.Join(dir, v+".mod"), mod, 0600))
	must(os.WriteFile(filepath.Join(dir, v+".info"), info, 0600))
	fmt.Println("VERIFIED", path, version)
}
