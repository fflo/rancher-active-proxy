# rancher-gen (RAP edition)

Template renderer that polls the Rancher v1 metadata service and regenerates
files (the nginx config and the Let's Encrypt host list) whenever services,
containers or labels change.

This is the source of `adi90x/rancher-gen-rap` (itself a fork of
[janeczku/go-rancher-gen](https://github.com/janeczku/go-rancher-gen)),
moved in-tree so the proxy image can be rebuilt without depending on the
long-expired GitLab CI artifact the original `Dockerfile` downloaded.

Changes from the original tree:

- Go modules (`go.mod` / `go.sum`) with pinned, checksum-verified dependencies.
- `github.com/Sirupsen/logrus` → `github.com/sirupsen/logrus` (the upper-case
  import path has been broken for years).
- Deprecated `io/ioutil` calls replaced with their `os` equivalents.
- Two `log.Info` calls that used printf verbs are now `log.Infof` (they used to
  print the literal `%d` / `%s`).

Template functions available on top of Go's `text/template`:
`base`, `cell`, `closest`, `coalesce`, `concatenateUnique`, `contains`, `dict`,
`dir`, `dirList`, `env`, `exists`, `filterHost`, `filterLabel`, `first`,
`formatClean`, `getAllLabelValue`, `groupByLabel`, `groupByMulti`,
`groupByMultiFilter`, `host`, `hosts`, `join`, `last`, `replace`, `service`,
`services`, `split`, `timestamp`, `toLower`, `toUpper`, `trim`, `trimSuffix`,
`when`, `whereLabelEquals`, `whereLabelExists`, `whereLabelMatches`.

Build locally:

```sh
cd rancher-gen
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o rancher-gen .
```
