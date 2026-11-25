# GitHub network download fixtures

Dedicated branch for xindong/test-repo network reproduction.

- git-16m.bin: 16 MiB random data stored in ordinary Git.
- lfs-128m.bin: 128 MiB random data stored in Git LFS; same bytes are also used as a Release asset.
- manifest.json records exact sizes and SHA256 checksums.

Run each transfer separately, using a fresh clone or fresh LFS cache. Compare fixed commits and file hashes. Do not treat authentication failures or truncated transfers as successful speed tests.

Use `bash network-probe/probe.sh baseline` for baseline collection. Run `bash network-probe/probe.sh --help` for individual transfer modes. Private Release downloads require authentication; do not share credentials or signed URLs.

The first run is on Jerry MacBook Air, not macos-206/207 or 172.26.63.144. Results from different subnets need network-side egress confirmation.
