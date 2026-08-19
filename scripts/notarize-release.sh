#!/usr/bin/env bash
#
# Build, sign, notarise, staple, and publish a ClipStory release.
#
#   ./scripts/notarize-release.sh v1.0.0
#
# Credentials come from .env (see .env.example). Secrets are never echoed.
# Re-running against an existing tag replaces the published asset in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG="${1:-}"
[[ -n "$TAG" ]] || { echo "usage: $0 <tag>   e.g. $0 v1.0.0" >&2; exit 2; }

# ---------------------------------------------------------------- config ----
[[ -f .env ]] || { echo "error: no .env — copy .env.example to .env first" >&2; exit 2; }
set -a; . ./.env; set +a

FORGEJO_API="${FORGEJO_API:-http://10.8.72.16/api/v1}"
FORGEJO_REPO="${FORGEJO_REPO:-bschmalz/ClipStory}"
GITHUB_REPO="${GITHUB_REPO:-bschmalz81401/ClipStory}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ClipStory/Resources/Info.plist)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
APP="$WORK/dd/Build/Products/Release/ClipStory.app"
ZIP="$WORK/ClipStory-${VERSION}.zip"

# Pick an auth route: keychain > api key > apple id.
NOTARY_AUTH=()
if [[ -n "${AC_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$AC_KEYCHAIN_PROFILE")
  echo "==> auth: keychain profile '$AC_KEYCHAIN_PROFILE'"
elif [[ -n "${AC_API_KEY_PATH:-}" ]]; then
  [[ -f "$AC_API_KEY_PATH" ]] || { echo "error: AC_API_KEY_PATH not found: $AC_API_KEY_PATH" >&2; exit 2; }
  NOTARY_AUTH=(--key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID")
  echo "==> auth: App Store Connect API key $AC_API_KEY_ID"
elif [[ -n "${AC_APPLE_ID:-}" ]]; then
  NOTARY_AUTH=(--apple-id "$AC_APPLE_ID" --password "$AC_APP_PASSWORD" --team-id "$AC_TEAM_ID")
  echo "==> auth: Apple ID $AC_APPLE_ID"
else
  echo "error: no credentials in .env — fill in one of the three routes" >&2; exit 2
fi

# ----------------------------------------------------------------- build ----
echo "==> regenerating project"
xcodegen generate >/dev/null

echo "==> building Release"
xcodebuild -scheme ClipStory -configuration Release \
  -derivedDataPath "$WORK/dd" clean build >"$WORK/build.log" 2>&1 \
  || { echo "build failed:" >&2; tail -40 "$WORK/build.log" >&2; exit 1; }

echo "==> verifying signature"
codesign --verify --deep --strict "$APP"

# Capture first, then match. Piping into `grep -q` under `set -o pipefail` is a
# race: grep exits on the first match, the writer takes SIGPIPE, and pipefail
# reports the pipeline as failed even though the pattern matched.
SIG_INFO="$(codesign -dvv "$APP" 2>&1)"
if ! grep -qE 'flags=0x[0-9a-f]*10000' <<<"$SIG_INFO"; then
  echo "error: hardened runtime missing. codesign reported:" >&2
  sed 's/^/    /' <<<"$SIG_INFO" >&2
  exit 1
fi

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if grep -q 'get-task-allow</key><true/>' <<<"$ENTITLEMENTS"; then
  echo "error: get-task-allow is true; notarisation will reject this" >&2
  exit 1
fi

# -------------------------------------------------------------- notarise ----
echo "==> submitting to Apple (this usually takes 1-5 min)"
ditto -c -k --keepParent "$APP" "$WORK/submit.zip"

SUBMIT_OUT="$WORK/submit.txt"
if ! xcrun notarytool submit "$WORK/submit.zip" "${NOTARY_AUTH[@]}" --wait 2>&1 | tee "$SUBMIT_OUT"; then
  echo "error: notarytool submit failed" >&2; exit 1
fi

if ! grep -q 'status: Accepted' "$SUBMIT_OUT"; then
  echo "error: notarisation was not accepted. Apple's log:" >&2
  SID="$(awk '/ id: [0-9a-f-]{36}/ {print $2; exit}' "$SUBMIT_OUT" || true)"
  [[ -n "$SID" ]] && xcrun notarytool log "$SID" "${NOTARY_AUTH[@]}" >&2
  exit 1
fi

echo "==> stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> repackaging with ticket attached"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper check"
spctl -a -vvv -t install "$APP" 2>&1 | sed 's/^/    /'
spctl -a -t install "$APP" 2>/dev/null \
  || { echo "error: Gatekeeper still rejects the app" >&2; exit 1; }

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "==> artifact ready: $(basename "$ZIP")  $(wc -c <"$ZIP" | tr -d ' ') bytes"
echo "    sha256 $SHA"

# --------------------------------------------------------------- publish ----
ASSET="$(basename "$ZIP")"

echo "==> uploading to GitHub ($GITHUB_REPO)"
gh release upload "$TAG" "$ZIP" --repo "$GITHUB_REPO" --clobber

echo "==> uploading to Forgejo ($FORGEJO_REPO)"
TOKEN="$(awk '/token:/ {print $2; exit}' "${TEA_CONFIG:-$HOME/Library/Application Support/tea/config.yml}")"
REL_JSON="$(curl -sf -H "Authorization: token $TOKEN" \
  "$FORGEJO_API/repos/$FORGEJO_REPO/releases/tags/$TAG")"
REL_ID="$(printf '%s' "$REL_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"

# Forgejo has no clobber; delete the old asset of the same name first.
OLD_ID="$(printf '%s' "$REL_JSON" | python3 -c "
import sys,json
for a in json.load(sys.stdin).get('assets',[]):
    if a['name']=='$ASSET': print(a['id']); break
")"
if [[ -n "$OLD_ID" ]]; then
  curl -sf -X DELETE -H "Authorization: token $TOKEN" \
    "$FORGEJO_API/repos/$FORGEJO_REPO/releases/$REL_ID/assets/$OLD_ID" >/dev/null
  echo "    replaced existing asset"
fi
curl -sf -X POST -H "Authorization: token $TOKEN" \
  -F "attachment=@$ZIP" \
  "$FORGEJO_API/repos/$FORGEJO_REPO/releases/$REL_ID/assets?name=$ASSET" >/dev/null

echo
echo "done — notarised $ASSET published to both remotes"
echo "  https://github.com/$GITHUB_REPO/releases/tag/$TAG"
echo "  ${FORGEJO_API%/api/v1}/$FORGEJO_REPO/releases/tag/$TAG"
