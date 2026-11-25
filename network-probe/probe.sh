#!/bin/bash
# macOS/Linux; each invocation writes to a fresh private directory.
set -eu
umask 077

usage() {
  cat <<'EOF'
Usage:
  bash probe.sh baseline
  bash probe.sh http LABEL DOWNLOAD_URL [SHA256]
  bash probe.sh lfs REPO_DIRECTORY COMMIT FILE_PATH

http: one curl transfer, at most 180 seconds; verify the optional SHA256.
lfs: fetch one file into a fresh cache without changing the working tree.
Results remain local. Private download URLs must not be shared in logs.
EOF
}

MODE=${1:---help}
case "$MODE" in
  --help|-h) usage; exit 0 ;;
  baseline) [ "$#" -eq 1 ] || { usage; exit 2; } ;;
  http) [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { usage; exit 2; } ;;
  lfs) [ "$#" -eq 4 ] || { usage; exit 2; } ;;
  *) usage; exit 2 ;;
esac

OUT=$(mktemp -d /tmp/github-network-probe.XXXXXX)
printf 'Results: %s\n' "$OUT"
{
  date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
  hostname
  uname -srm
  printf 'mode=%s\n' "$MODE"
} > "$OUT/context.txt"

case "$MODE" in
  baseline)
    if command -v sw_vers >/dev/null 2>&1; then
      sw_vers > "$OUT/os.txt"
      /sbin/route -n get default > "$OUT/default-route.txt" 2>&1 || true
      # Capture enabled flags only, without PAC URLs or proxy credentials.
      /usr/sbin/scutil --proxy | awk '/Enable[[:space:]]*:/ { print }' > "$OUT/proxy-flags.txt"
    fi
    for domain in github.com github-cloud.githubusercontent.com objects.githubusercontent.com codeload.github.com; do
      if command -v dig >/dev/null 2>&1; then
        { printf '%s\n' "$domain"; dig +time=3 +tries=1 +short "$domain" A; dig +time=3 +tries=1 +short "$domain" AAAA; } >> "$OUT/dns.txt"
      fi
    done
    if command -v networkQuality >/dev/null 2>&1; then
      networkQuality -s > "$OUT/networkQuality.txt" 2>&1
    fi
    ;;
  http)
    printf 'label=%s\n' "$2" >> "$OUT/context.txt"
    # -q ignores .curlrc; existing proxy environment variables still apply.
    if curl -q --fail --location --silent --show-error \
      --connect-timeout 15 --max-time 180 --retry 0 \
      --output "$OUT/payload" \
      --write-out 'http_code=%{http_code}\nremote_ip=%{remote_ip}\nbytes=%{size_download}\nseconds=%{time_total}\nbytes_per_second=%{speed_download}\nfirst_byte_seconds=%{time_starttransfer}\n' \
      "$3" > "$OUT/transfer.txt" 2> "$OUT/error.txt"; then
      if [ -n "${4:-}" ]; then
        actual=$(shasum -a 256 "$OUT/payload" | awk '{print $1}')
        if [ "$actual" != "$4" ]; then
          printf 'status=checksum_failed\n' >> "$OUT/transfer.txt"
          cat "$OUT/transfer.txt"
          exit 1
        fi
      fi
      printf 'status=success\n' >> "$OUT/transfer.txt"
      cat "$OUT/transfer.txt"
    else
      rc=$?
      printf 'status=failed\ncurl_exit=%s\n' "$rc" >> "$OUT/transfer.txt"
      cat "$OUT/transfer.txt"
      exit "$rc"
    fi
    ;;
  lfs)
    cd "$2"
    git lfs version > "$OUT/git-lfs-version.txt"
    ref=$(git rev-parse --verify "$3^{commit}")
    git show "$ref:$4" > "$OUT/pointer.txt"
    grep -q '^version https://git-lfs.github.com/spec/v1$' "$OUT/pointer.txt" || { printf 'Selected path is not an LFS pointer\n' >&2; exit 2; }
    printf 'commit=%s\nfile=%s\n' "$ref" "$4" >> "$OUT/context.txt"
    if /usr/bin/time -p git -c lfs.storage="$OUT/lfs" \
      -c lfs.concurrenttransfers=1 -c lfs.fetchrecentalways=false \
      lfs fetch --include="$4" --exclude='' origin "$ref" \
      > "$OUT/fetch.stdout" 2> "$OUT/fetch.stderr"; then
      printf 'status=success\n' > "$OUT/result.txt"
    else
      rc=$?
      printf 'status=failed\nexit=%s\n' "$rc" > "$OUT/result.txt"
      exit "$rc"
    fi
    ;;
esac
