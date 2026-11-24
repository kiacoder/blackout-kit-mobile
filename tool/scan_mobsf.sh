#!/usr/bin/env bash
set -euo pipefail
dist="${1:?distribution directory required}"
if [[ -z "${MOBSF_IMAGE:-}" ]]; then
  printf '%s\n' '{"status":"not-configured","reason":"Set a reviewed official MobSF image digest"}' > "$dist/MOBSF_STATUS.json"
  exit 0
fi
if [[ ! "$MOBSF_IMAGE" =~ ^opensecurity/mobile-security-framework-mobsf@sha256:[a-f0-9]{64}$ ]]; then
  echo "MobSF image must be pinned to an official SHA-256 digest" >&2
  exit 1
fi
key=$(openssl rand -hex 32)
echo "::add-mask::$key"
name="mobsf-ci-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -p 127.0.0.1:8000:8000 \
  -e MOBSF_API_KEY="$key" -e MOBSF_DOMAIN_MALWARE_SCAN=0 -e MOBSF_VT_UPLOAD=0 "$MOBSF_IMAGE"
ready=false
for i in $(seq 1 90); do
  if curl -fsS --max-time 3 http://127.0.0.1:8000/ >/dev/null; then ready=true; break; fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  echo "MobSF readiness timeout" >&2
  exit 1
fi
for apk in "$dist"/*-universal.apk; do
  upload=$(curl --fail-with-body -sS --max-time 180 -H "Authorization: $key" -F "file=@$apk" http://127.0.0.1:8000/api/v1/upload)
  hash=$(jq -er '.hash | select(test("^[a-f0-9]{32}$"))' <<< "$upload")
  test "$hash" = "$(md5sum "$apk" | cut -d' ' -f1)"
  curl --fail-with-body -sS --max-time 900 -H "Authorization: $key" --data-urlencode "hash=$hash" http://127.0.0.1:8000/api/v1/scan > /tmp/mobsf-scan.json
  curl --fail-with-body -sS --max-time 120 -H "Authorization: $key" --data-urlencode "hash=$hash" http://127.0.0.1:8000/api/v1/report_json > "$dist/MOBSF_REPORT.json"
  apk_sha=$(sha256sum "$apk" | cut -d' ' -f1)
  jq -e --arg md5 "$hash" --arg sha "$apk_sha" 'type == "object" and (has("error") | not) and length > 10 and .md5 == $md5 and .sha256 == $sha' "$dist/MOBSF_REPORT.json" >/dev/null
done
jq -n --arg image "$MOBSF_IMAGE" '{status:"completed-review-required",image:$image,scope:"universal APK static analysis only"}' > "$dist/MOBSF_STATUS.json"
