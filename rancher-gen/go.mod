module github.com/fflo/rancher-gen-rap

go 1.23

require (
	github.com/BurntSushi/toml v1.4.0
	github.com/rancher/go-rancher-metadata v0.0.0-20200311180630-7f4c936a06ac
	github.com/sirupsen/logrus v1.9.3
)

require golang.org/x/sys v0.0.0-20220715151400-c0bba94af5f8 // indirect

// The vanity import hosts (golang.org, gopkg.in) are mapped to their official
// GitHub mirrors so the module graph resolves from a single, pinnable origin.
// The replacement modules declare the original module paths, so the Go
// toolchain verifies them exactly as it would the originals.
replace golang.org/x/sys => github.com/golang/sys v0.26.0

replace gopkg.in/yaml.v3 => github.com/go-yaml/yaml v0.0.0-20220527083530-f6f7691b1fde

replace gopkg.in/check.v1 => github.com/go-check/check v0.0.0-20180628173108-788fd7840127
