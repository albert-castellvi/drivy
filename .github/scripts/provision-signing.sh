#!/usr/bin/env bash
#
# Drivy — create the iOS distribution certificate and the App Store
# provisioning profile through the App Store Connect REST API (S11 / T8).
#
# Why this exists
# ---------------
# `xcodebuild archive` with automatic cloud signing failed on team QP5A6D4Y4P
# with "Your team has no devices from which to generate a provisioning profile"
# plus "No profiles for 'com.acrstudio.drivy' were found: ... iOS App
# Development provisioning profiles": the team has no distribution certificate
# yet, so Xcode fell back to development provisioning. This script does what
# fastlane `match` / `spaceship` do with an API key, *before* the archive runs:
#
#   0. ES256 JWT, signed with the already-installed .p8, openssl only.
#   1. App ID      GET  /v1/bundleIds?filter[identifier]=<bundle>
#                  POST /v1/bundleIds                            (if missing)
#      Capability  GET  /v1/bundleIds/<id>/bundleIdCapabilities
#                  POST /v1/bundleIdCapabilities  SIGN_IN_WITH_APPLE
#                                                 (409 = already enabled)
#   2. Certificate GET  /v1/certificates?filter[certificateType]=DISTRIBUTION
#                  POST /v1/certificates  certificateType=DISTRIBUTION + CSR
#                  -> certificateContent (base64 DER leaf) -> .p12 with a
#                     random export password -> temporary job keychain
#   3. Profile     GET  /v1/profiles?filter[name]=<profile>&include=bundleId
#                  GET  /v1/profiles/<id>/certificates
#                  POST /v1/profiles  IOS_APP_STORE + bundleId + certificate
#                  -> profileContent -> installed in the runner profiles dir
#
# Deliberately non-destructive: nothing is ever revoked, deleted or updated in
# the developer portal. The only writes are POSTs that create missing records.
#
# Everything signing-related lives on the ephemeral runner. The CSR private key
# is generated here with openssl (EC P-256, as Apple requires), the .p12 export
# password and the keychain password are random, and neither passwords, the
# private key, the JWT, nor the .p8 content is ever echoed: no `set -x`.
#
# Inputs (env):
#   ASC_KEY_ID, ASC_ISSUER_ID          required; the App Store Connect API key
#   ASC_KEY_PATH                       default $HOME/private_keys/AuthKey_<ID>.p8
#   APPLE_TEAM_ID                      default QP5A6D4Y4P
#   BUNDLE_ID                          default com.acrstudio.drivy
#   APP_NAME                           default Drivy
#   PROFILE_NAME                       default "Drivy App Store CI"
#   ASC_API_BASE                       override for tests only
#
# Outputs (written to $GITHUB_ENV):
#   PROFILE_NAME            read by the archive/export steps (profile specifier)
#   SIGNING_KEYCHAIN_PATH   read by the keychain cleanup step
#
# A pre-existing distribution certificate is reused only when its private key
# is already in a searched keychain (the workflow imports it with
# the DIST_CERTIFICATE_P12_BASE64 secret). Otherwise the script stops with an explicit
# error (see `existing certificate` below) instead of revoking anything.

set -euo pipefail

ASC_API_BASE="${ASC_API_BASE:-https://api.appstoreconnect.apple.com}"
ASC_KEY_ID="${ASC_KEY_ID:?ASC_KEY_ID must be set}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?ASC_ISSUER_ID must be set}"
TEAM_ID="${APPLE_TEAM_ID:-QP5A6D4Y4P}"
BUNDLE_ID="${BUNDLE_ID:-com.acrstudio.drivy}"
APP_NAME="${APP_NAME:-Drivy}"
PROFILE_NAME="${PROFILE_NAME:-Drivy App Store CI}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/drivy-signing"
KEYCHAIN="$WORK/Drivy-signing.keychain-db"
CERT_RESOURCE_ID=""
PROFILE_RESOURCE_ID=""
# Defaults so the script can also be inspected/run outside a workflow step.
GITHUB_ENV="${GITHUB_ENV:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

info() { echo "$*"; }
warn() { echo "::warning::$*"; }

# Prints an App Store Connect error and stops. Every line after the first is
# emitted as plain log text (only the first line becomes an annotation).
die() {
  echo "::error::$1"
  shift || true
  local line
  for line in "$@"; do
    echo "$line"
  done
  exit 1
}

# Last chunk of the current API response, for error messages. Responses never
# contain credentials; the JWT only ever travels in the request header.
response_snippet() {
  head -c 800 "$API_BODY" 2>/dev/null || true
  echo
}

# ---------------------------------------------------------------- primitives

b64url_encode() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

b64decode() { # <input file> <output file>
  if ! base64 -D <"$1" >"$2" 2>/dev/null; then
    # GNU coreutils spelling, kept as a portability net (Linux containers).
    base64 --decode <"$1" >"$2"
  fi
  [ -s "$2" ] || die "Decoding $(basename "$1") produced an empty file."
}

# ECDSA: `openssl dgst -sign` emits DER (SEQUENCE of two INTEGERs), while JWS
# ES256 needs the fixed 64-byte r||s concatenation. This is the classic
# DER->raw pitfall: r and s are variable length (33 bytes whenever the high bit
# is set, because DER prepends 0x00 to keep the integer positive), so both need
# to be left-padded to exactly 32 bytes.
normalize_der_integer() { # <hex> -> exactly 64 hex chars
  local h
  h="$(printf '%s' "$1" | tr 'A-F' 'a-f')"
  # Errors go to stderr with a non-zero return: this runs inside a command
  # substitution, where `die` would inject its message into the hex string.
  [ -n "$h" ] || { echo "empty ECDSA integer" >&2; return 1; }
  while [ "${#h}" -gt 64 ]; do
    [ "${h:0:2}" = "00" ] \
      || { echo "ECDSA integer longer than 32 bytes (${#h} hex chars); not a P-256 signature" >&2; return 1; }
    h="${h:2}"
  done
  while [ "${#h}" -lt 64 ]; do
    h="0$h"
  done
  printf '%s' "$h"
}

# <DER file> -> 128 hex chars (r||s). Parsed with openssl asn1parse so no extra
# JSON/ASN.1 dependency is needed on the runner.
der_signature_to_raw_hex() {
  local der="$1" integers r s
  integers="$(openssl asn1parse -inform DER -in "$der" 2>/dev/null \
    | awk -F: '/prim:[[:space:]]*INTEGER/ { print $NF }')" \
    || die "Could not parse the ECDSA signature returned by openssl dgst."
  r="$(printf '%s\n' "$integers" | sed -n '1p' | tr -d '[:space:]')"
  s="$(printf '%s\n' "$integers" | sed -n '2p' | tr -d '[:space:]')"
  [ -n "$r" ] && [ -n "$s" ] \
    || die "The ECDSA signature is not a two-integer DER sequence (r='$r' s='$s')."
  r="$(normalize_der_integer "$r")" || die "The DER signature is not a P-256 ECDSA signature (r)."
  s="$(normalize_der_integer "$s")" || die "The DER signature is not a P-256 ECDSA signature (s)."
  printf '%s%s' "$r" "$s"
}

# <hex bytes> -> standard base64, single line. Binary never travels through a
# command substitution (bash silently drops NUL bytes there), only through a
# pipe: text -> escaped text -> `printf %b` stream -> base64.
hex_to_base64() {
  local escaped
  escaped="$(printf '%s' "$1" | sed 's/../\\x&/g')"
  printf '%b' "$escaped" | openssl base64 -A
}

# ------------------------------------------------------------- JSON helpers
# python3 is already a hard dependency of this workflow (project validation in
# ci.yml), which is why it is preferred over jq here.

# <file> <dotted.path> -> value on stdout, empty when missing.
json_path() {
  python3 - "$@" <<'PY'
import json, sys
node = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    if key == "":
        continue
    if isinstance(node, list):
        try:
            node = node[int(key)]
        except (IndexError, ValueError):
            sys.exit(0)
    elif isinstance(node, dict):
        if key not in node:
            sys.exit(0)
        node = node[key]
    else:
        sys.exit(0)
if node is None:
    sys.exit(0)
print(node if not isinstance(node, (dict, list)) else json.dumps(node))
PY
}

# <file> <dotted field>... -> one TAB-separated line per `data[]` element.
json_rows() {
  python3 - "$@" <<'PY'
import json, sys

def get(node, dotted):
    for key in dotted.split("."):
        if node is None:
            return ""
        if isinstance(node, list):
            node = node[int(key)] if key.isdigit() and int(key) < len(node) else None
        elif isinstance(node, dict):
            node = node.get(key)
        else:
            return ""
    return "" if node is None else node

doc = json.load(open(sys.argv[1]))
for item in doc.get("data") or []:
    print("\t".join(str(get(item, field)) for field in sys.argv[2:]))
PY
}

# <file> <profile name> <bundle resource id> -> usable profile resource id.
json_select_profile_id() {
  python3 - "$@" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
name, bundle_resource_id = sys.argv[2], sys.argv[3]
for item in doc.get("data") or []:
    attributes = item.get("attributes") or {}
    relationship = ((item.get("relationships") or {}).get("bundleId") or {}).get("data") or {}
    if (
        attributes.get("name") == name
        and relationship.get("id") == bundle_resource_id
        and attributes.get("profileState", "ACTIVE") == "ACTIVE"
    ):
        print(item["id"])
        sys.exit(0)
PY
}

# ----------------------------------------------------------------- API calls

API_STATUS=""
API_BODY=""

# <METHOD> <path+query> [body file] -> sets API_STATUS / API_BODY.
# Brackets in App Store Connect query strings are percent-encoded in callers,
# and --globoff covers any that slip through: curl would otherwise read
# `filter[identifier]` as a URL glob range.
api_call() {
  local method="$1" path="$2" body_file="${3:-}"
  local url="${ASC_API_BASE}${path}"
  local out="$WORK/api-body.json"
  local attempt=1 status
  while :; do
    local args=(
      -sS --globoff -X "$method"
      --config "$WORK/curl-auth.conf"
      -H 'Accept: application/json'
      -o "$out" -w '%{http_code}'
    )
    if [ -n "$body_file" ]; then
      args+=(-H 'Content-Type: application/json' --data-binary "@$body_file")
    fi
    status="$(curl "${args[@]}" "$url")" \
      || die "curl could not reach the App Store Connect API ($method $path)."
    case "$status" in
      429|500|502|503|504)
        if [ "$attempt" -lt 3 ]; then
          attempt=$((attempt + 1))
          warn "App Store Connect returned HTTP $status for $method $path; retrying (attempt $attempt/3)."
          sleep $((attempt * 5))
          continue
        fi
        ;;
    esac
    API_STATUS="$status"
    API_BODY="$out"
    return 0
  done
}

# Re-signs the request with a fresh JWT. Tokens live 20 minutes (Apple's max).
refresh_token() {
  local iat exp header payload signing_input raw_hex signature
  iat="$(date -u +%s)"
  exp=$((iat + 1200))
  header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID")"
  payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
    "$ASC_ISSUER_ID" "$iat" "$exp")"
  signing_input="$(printf '%s' "$header" | b64url_encode).$(printf '%s' "$payload" | b64url_encode)"
  printf '%s' "$signing_input" >"$WORK/jwt-signing-input"

  # DER signature straight to a file: never through a pipe into a variable.
  openssl dgst -sha256 -sign "$KEY_PATH" -out "$WORK/jwt-signature.der" \
    "$WORK/jwt-signing-input" 2>"$WORK/jwt-sign-error" \
    || die "Could not sign the ASC JWT with the installed .p8 (openssl dgst failed)." \
           "$(cat "$WORK/jwt-sign-error")"

  raw_hex="$(der_signature_to_raw_hex "$WORK/jwt-signature.der")"
  signature="$(hex_to_base64 "$raw_hex" | tr '+/' '-_' | tr -d '=')"
  JWT="$(printf '%s.%s' "$signing_input" "$signature")"

  # The JWT is a bearer credential for the whole team: mask it in the log, keep
  # it in a 0600 curl config so it never shows up in a process listing.
  echo "::add-mask::$JWT"
  printf 'header = "Authorization: Bearer %s"\n' "$JWT" >"$WORK/curl-auth.conf"
  chmod 600 "$WORK/curl-auth.conf"
}

# ------------------------------------------------------------------- script

[ -f "$KEY_PATH" ] || die "App Store Connect API key not found at the masked expected path."
[ -s "$KEY_PATH" ] || die "App Store Connect API key file is empty."

# Start from an empty scratch directory; nothing is reused between runs.
mkdir -p "$WORK"
chmod 700 "$WORK"
API_BODY="$WORK/api-body.json"
JWT=""
refresh_token
info "ASC API JWT minted (ES256, 20 min) — value never printed."

# --- 1. App ID -------------------------------------------------------------

info "Ensuring App ID $BUNDLE_ID exists in team $TEAM_ID..."
api_call GET "/v1/bundleIds?filter%5Bidentifier%5D=${BUNDLE_ID}&limit=200"
case "$API_STATUS" in
  200) ;;
  *) die "GET /v1/bundleIds failed (HTTP $API_STATUS)." "$(response_snippet)" ;;
esac

BUNDLE_RESOURCE_ID="$(json_rows "$API_BODY" id attributes.identifier \
  | awk -F'\t' -v want="$BUNDLE_ID" '$2 == want { print $1; exit }')"

if [ -z "$BUNDLE_RESOURCE_ID" ]; then
  info "App ID not found; POST /v1/bundleIds."
  python3 - "$WORK/bundle-request.json" "$BUNDLE_ID" "$APP_NAME" <<'PY'
import json, sys
json.dump(
    {"data": {"type": "bundleIds", "attributes": {
        "identifier": sys.argv[2], "name": sys.argv[3], "platform": "IOS"}}},
    open(sys.argv[1], "w"),
)
PY
  api_call POST /v1/bundleIds "$WORK/bundle-request.json"
  case "$API_STATUS" in
    200|201)
      BUNDLE_RESOURCE_ID="$(json_path "$API_BODY" data.id)"
      info "Created App ID $BUNDLE_ID (resource $BUNDLE_RESOURCE_ID)."
      ;;
    409)
      # Raced with another run or created seconds ago: re-read it.
      api_call GET "/v1/bundleIds?filter%5Bidentifier%5D=${BUNDLE_ID}&limit=200"
      BUNDLE_RESOURCE_ID="$(json_rows "$API_BODY" id attributes.identifier \
        | awk -F'\t' -v want="$BUNDLE_ID" '$2 == want { print $1; exit }')"
      [ -n "$BUNDLE_RESOURCE_ID" ] \
        || die "POST /v1/bundleIds returned 409 but the App ID is still not listed." "$(response_snippet)"
      ;;
    403)
      die "The API key is not allowed to create App IDs (HTTP 403). It needs the App Manager or Admin role." \
          "$(response_snippet)"
      ;;
    *)
      die "POST /v1/bundleIds failed (HTTP $API_STATUS)." "$(response_snippet)"
      ;;
  esac
else
  info "App ID exists (resource $BUNDLE_RESOURCE_ID)."
fi

[ -n "$BUNDLE_RESOURCE_ID" ] || die "Could not resolve the App ID resource id."

# --- 1b. Sign in with Apple capability -------------------------------------

info "Ensuring the Sign in with Apple capability is enabled on the App ID..."
# No GET pre-check: the capabilities collection endpoint is forbidden to some
# API-key roles; POST reports 409 when it is already enabled.
python3 - "$WORK/capability-request.json" "$BUNDLE_RESOURCE_ID" <<'PY'
import json, sys
json.dump(
    {"data": {
        "type": "bundleIdCapabilities",
        "attributes": {"capabilityType": "SIGN_IN_WITH_APPLE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": sys.argv[2]}}},
    }},
    open(sys.argv[1], "w"),
)
PY
api_call POST /v1/bundleIdCapabilities "$WORK/capability-request.json"
case "$API_STATUS" in
  200|201) info "SIGN_IN_WITH_APPLE enabled (this removes the manual portal step from S10)." ;;
  409) info "SIGN_IN_WITH_APPLE was already enabled (HTTP 409 Conflict); continuing." ;;
  403)
    die "POST /v1/bundleIdCapabilities failed (HTTP 403 Forbidden)." \
        "The API key role cannot manage capabilities. Either raise the key to Admin in App Store Connect (Users and Access -> Integrations) or enable Sign in with Apple manually on App ID com.acrstudio.drivy in Certificates, Identifiers & Profiles." \
        "The app's entitlements require it (S10/L7), so the archive would fail without it." \
        "$(response_snippet)"
    ;;
  *)
    die "POST /v1/bundleIdCapabilities failed (HTTP $API_STATUS)." \
        "The App ID must carry Sign in with Apple: the app's entitlements require it (S10/L7), so the archive would fail without it." \
        "$(response_snippet)"
    ;;
esac

# --- 2. Distribution certificate -------------------------------------------

info "Looking for an existing Apple Distribution certificate in team $TEAM_ID..."
api_call GET "/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=200"
case "$API_STATUS" in
  200) ;;
  *) die "GET /v1/certificates failed (HTTP $API_STATUS)." "$(response_snippet)" ;;
esac

existing_certs="$(json_rows "$API_BODY" id attributes.certificateType attributes.displayName attributes.expirationDate attributes.certificateContent \
  | awk -F'\t' '$2 == "DISTRIBUTION" || $2 == "IOS_DISTRIBUTION"')"

if [ -z "$existing_certs" ]; then
  # Older teams hold the legacy `IOS_DISTRIBUTION` type (Apple added the generic
  # `DISTRIBUTION`/`DEVELOPMENT` types later), and the filtered query can come
  # back empty even though a distribution cert exists. One unfiltered read is
  # enough to be sure before creating anything.
  api_call GET "/v1/certificates?limit=200"
  if [ "$API_STATUS" = "200" ]; then
    existing_certs="$(json_rows "$API_BODY" id attributes.certificateType attributes.displayName attributes.expirationDate attributes.certificateContent \
      | awk -F'\t' '$2 == "DISTRIBUTION" || $2 == "IOS_DISTRIBUTION"')"
  fi
fi

# A distribution certificate whose private key is already in a searched keychain
# is reused as is: the workflow imports the team's shared identity from the
# DIST_CERTIFICATE_P12_BASE64 secret (same .p12 as ProofMate) before this script.
# Matching is by SHA-1 of the DER certificate, which is what find-identity lists.
signing_identities="$(security find-identity -v -p codesigning 2>/dev/null | awk '{print $2}')"
if [ -n "$existing_certs" ] && [ -n "$signing_identities" ]; then
  while IFS=$'\t' read -r id _type _name expiry content; do
    sha1="$(printf '%s' "$content" | openssl base64 -d -A | openssl sha1 | awk '{print toupper($NF)}')"
    if printf '%s\n' "$signing_identities" | grep -qx "$sha1"; then
      CERT_RESOURCE_ID="$id"
      cert_expiry="$expiry"
      KEYCHAIN="${IMPORTED_KEYCHAIN_PATH:-$KEYCHAIN}"
      info "Reusing Apple Distribution certificate $CERT_RESOURCE_ID (expires ${cert_expiry:-unknown}); its private key is already in the keychain."
      break
    fi
  done <<<"$existing_certs"
fi

if [ -z "$CERT_RESOURCE_ID" ]; then
  if [ -n "$existing_certs" ]; then
    first_cert="$(printf '%s\n' "$existing_certs" | sed -n '1p')"
    cert_id="$(printf '%s' "$first_cert" | cut -f1)"
    cert_type="$(printf '%s' "$first_cert" | cut -f2)"
    cert_name="$(printf '%s' "$first_cert" | cut -f3)"
    cert_expiry="$(printf '%s' "$first_cert" | cut -f4)"
    die "Team $TEAM_ID already has an Apple Distribution certificate (id $cert_id, type $cert_type, name '${cert_name:-?}', expires ${cert_expiry:-?}), but none of the team's distribution certificates has its private key in a keychain on this runner." \
        "" \
        "Nothing was revoked or changed (revoking a certificate without explicit human approval is not acceptable)." \
        "To continue, pick one of these:" \
        "  1. Revoke/delete that certificate in the Apple Developer portal (Certificates, Identifiers & Profiles -> Certificates) and re-run this job: it will create a fresh distribution certificate together with its private key." \
        "  2. Check the DIST_CERTIFICATE_P12_BASE64 / DIST_CERTIFICATE_PASSWORD secrets: the 'Import distribution identity (.p12)' step must import one of the certificates above before this script runs." \
        "" \
        "Other distribution certificates in the team: $(printf '%s\n' "$existing_certs" | cut -f1 | tr '\n' ' ')"
  fi

  info "No distribution certificate yet; generating a fresh EC P-256 key and CSR..."
  # Apple requires an EC P-256 key; the key and the .p12 stay inside $WORK, which
  # exists only for this run.
  openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/csr-key.pem" 2>"$WORK/openssl-ec-error" \
    || die "openssl could not generate the EC P-256 private key." "$(cat "$WORK/openssl-ec-error")"
  chmod 600 "$WORK/csr-key.pem"
  openssl req -new -sha256 -key "$WORK/csr-key.pem" \
    -subj "/CN=${APP_NAME} CI Distribution/O=ACRStudio/C=ES" \
    -out "$WORK/csr.pem" 2>"$WORK/openssl-csr-error" \
    || die "openssl could not build the CSR." "$(cat "$WORK/openssl-csr-error")"

  python3 - "$WORK/certificate-request.json" "$WORK/csr.pem" DISTRIBUTION <<'PY'
import json, sys
csr = open(sys.argv[2]).read()
json.dump(
    {"data": {"type": "certificates", "attributes": {
        "certificateType": sys.argv[3], "csrContent": csr}}},
    open(sys.argv[1], "w"),
)
PY

  # `DISTRIBUTION` is the current name of the "Apple Distribution" type; some
  # accounts still answer 400 for it and only accept the legacy `IOS_DISTRIBUTION`
  # spelling. Retrying is safe: a 400 means nothing was created.
  info "POST /v1/certificates (certificateType DISTRIBUTION)..."
  api_call POST /v1/certificates "$WORK/certificate-request.json"
  if [ "$API_STATUS" = "400" ]; then
    warn "App Store Connect rejected certificateType DISTRIBUTION (HTTP 400); retrying with the legacy IOS_DISTRIBUTION type."
    python3 - "$WORK/certificate-request.json" "$WORK/csr.pem" IOS_DISTRIBUTION <<'PY'
import json, sys
csr = open(sys.argv[2]).read()
json.dump(
    {"data": {"type": "certificates", "attributes": {
        "certificateType": sys.argv[3], "csrContent": csr}}},
    open(sys.argv[1], "w"),
)
PY
    api_call POST /v1/certificates "$WORK/certificate-request.json"
  fi
  case "$API_STATUS" in
    200|201) ;;
    409)
      die "POST /v1/certificates returned 409 Conflict: the team's distribution certificate limit is probably reached." \
          "Apple caps distribution certificates per team, and each one this pipeline creates is unusable for the next run (the private key is discarded with the runner)." \
          "Revoke an old certificate in the developer portal (explicit human decision) and re-run." \
          "$(response_snippet)"
      ;;
    403)
      die "The API key is not allowed to create certificates (HTTP 403). It needs the App Manager or Admin role." \
          "$(response_snippet)"
      ;;
    *)
      die "POST /v1/certificates failed (HTTP $API_STATUS)." "$(response_snippet)"
      ;;
  esac

  CERT_RESOURCE_ID="$(json_path "$API_BODY" data.id)"
  cert_expiry="$(json_path "$API_BODY" data.attributes.expirationDate)"
  [ -n "$CERT_RESOURCE_ID" ] || die "POST /v1/certificates returned no resource id." "$(response_snippet)"
  json_path "$API_BODY" data.attributes.certificateContent >"$WORK/certificate.b64"
  [ -s "$WORK/certificate.b64" ] || die "POST /v1/certificates returned no certificateContent."
  b64decode "$WORK/certificate.b64" "$WORK/certificate.cer"
  openssl x509 -inform DER -in "$WORK/certificate.cer" -out "$WORK/certificate.pem" 2>"$WORK/openssl-x509-error" \
    || die "The downloaded certificate is not valid DER X.509." "$(cat "$WORK/openssl-x509-error")"
  info "Created Apple Distribution certificate $CERT_RESOURCE_ID (expires ${cert_expiry:-unknown})."

  # .p12 with a random export password; the password goes through a 0600 file, not
  # through the command line, and is never printed.
  openssl rand -hex 24 >"$WORK/p12.pass"
  chmod 600 "$WORK/p12.pass"
  openssl pkcs12 -export \
    -inkey "$WORK/csr-key.pem" \
    -in "$WORK/certificate.pem" \
    -out "$WORK/signing.p12" \
    -name "$PROFILE_NAME" \
    -passout "file:$WORK/p12.pass" 2>"$WORK/openssl-pkcs12-error" \
    || die "openssl could not export the .p12." "$(cat "$WORK/openssl-pkcs12-error")"
  chmod 600 "$WORK/signing.p12"

  # --- 2b. Import into a throwaway job keychain ------------------------------

  info "Importing the identity into a temporary keychain..."
  openssl rand -hex 24 >"$WORK/keychain.pass"
  chmod 600 "$WORK/keychain.pass"
  KEYCHAIN_PASS="$(cat "$WORK/keychain.pass")"
  P12_PASS="$(cat "$WORK/p12.pass")"

  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"

  # codesign needs the issuing WWDR intermediate to validate the chain. Xcode's
  # install normally leaves it in the System keychain; import it when it is not
  # there so the identity is usable even on a bare image.
  if ! security find-certificate -c "Apple Worldwide Developer Relations" >/dev/null 2>&1; then
    if curl -sS -o "$WORK/wwdr.cer" -L https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer; then
      security import "$WORK/wwdr.cer" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null 2>&1 \
        && info "Imported the Apple WWDR G3 intermediate into the job keychain." \
        || warn "Could not import the Apple WWDR G3 intermediate; relying on the System keychain."
    else
      warn "Could not download the Apple WWDR G3 intermediate; relying on the System keychain."
    fi
  else
    info "Apple WWDR intermediate already present in a searched keychain."
  fi

  # The .p12 is the primary path. LibreSSL's PBES2/AES dialect is accepted by
  # recent macOS, but if the Security framework ever refuses it, the same identity
  # is imported from PEM (certificate + PKCS#8 key) instead of failing the job.
  if security import "$WORK/signing.p12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild; then
    info "Imported the .p12 identity into the job keychain."
  else
    warn "security import rejected the .p12 (LibreSSL/Keychain dialect); importing the PEM certificate and PKCS#8 key instead."
    openssl pkcs8 -topk8 -nocrypt -in "$WORK/csr-key.pem" -out "$WORK/csr-key-pkcs8.pem" \
      || die "openssl could not convert the CSR key to PKCS#8 for the keychain fallback."
    security import "$WORK/certificate.pem" -k "$KEYCHAIN" -T /usr/bin/codesign \
      || die "security import rejected the distribution certificate PEM."
    security import "$WORK/csr-key-pkcs8.pem" -k "$KEYCHAIN" \
      -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild \
      || die "security import rejected the PKCS#8 private key PEM."
    info "Imported the identity from PEM into the job keychain."
  fi
  # Without the partition list codesign cannot use the private key non-interactively.
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1 \
    || die "security set-key-partition-list failed on the job keychain."

  # Put the job keychain first in the user search list, keeping the existing ones.
  existing_keychains="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')"
  # shellcheck disable=SC2086 # deliberate word splitting: one argument per keychain
  security list-keychains -d user -s "$KEYCHAIN" $existing_keychains

  security find-identity -v -p codesigning "$KEYCHAIN" | grep -q 'Apple Distribution' \
    || die "The Apple Distribution identity is not usable in the job keychain." \
           "security find-identity output: $(security find-identity -v -p codesigning "$KEYCHAIN")"
  info "Codesigning identity available: Apple Distribution."
fi

# --- 3. App Store provisioning profile -------------------------------------

info "Looking for an App Store provisioning profile '$PROFILE_NAME' for $BUNDLE_ID..."
api_call GET "/v1/profiles?filter%5Bname%5D=$(printf '%s' "$PROFILE_NAME" | sed 's/ /%20/g')&include=bundleId&limit=200"
[ "$API_STATUS" = "200" ] || die "GET /v1/profiles failed (HTTP $API_STATUS)." "$(response_snippet)"

PROFILE_RESOURCE_ID="$(json_select_profile_id "$API_BODY" "$PROFILE_NAME" "$BUNDLE_RESOURCE_ID")"
profile_content_file=""

if [ -n "$PROFILE_RESOURCE_ID" ]; then
  info "Profile exists (resource $PROFILE_RESOURCE_ID); checking it covers certificate $CERT_RESOURCE_ID..."
  api_call GET "/v1/profiles/${PROFILE_RESOURCE_ID}/certificates?limit=200"
  [ "$API_STATUS" = "200" ] || die "GET /v1/profiles/${PROFILE_RESOURCE_ID}/certificates failed (HTTP $API_STATUS)." \
    "$(response_snippet)"
  if ! json_rows "$API_BODY" id | grep -qx "$CERT_RESOURCE_ID"; then
    die "The profile '$PROFILE_NAME' is registered for $BUNDLE_ID but does not include the distribution certificate $CERT_RESOURCE_ID this run must sign with." \
        "Nothing was deleted. Xcode would either ignore the profile or pick the wrong certificate." \
        "Delete that profile in the developer portal (Profiles -> '$PROFILE_NAME') and re-run this job, which will create a new one bound to the new certificate."
  fi
  # The download endpoint returns the .mobileprovision base64-encoded.
  api_call GET "/v1/profiles/${PROFILE_RESOURCE_ID}"
  [ "$API_STATUS" = "200" ] || die "GET /v1/profiles/${PROFILE_RESOURCE_ID} failed (HTTP $API_STATUS)." \
    "$(response_snippet)"
  json_path "$API_BODY" data.attributes.profileContent >"$WORK/profile.b64"
  profile_content_file="$WORK/profile.b64"
else
  info "No usable profile found; POST /v1/profiles (IOS_APP_STORE)..."
  # An App Store profile has no devices: the `devices` relationship must be
  # omitted (an empty array is rejected by the API).
  python3 - "$WORK/profile-request.json" "$PROFILE_NAME" "$BUNDLE_RESOURCE_ID" "$CERT_RESOURCE_ID" <<'PY'
import json, sys
json.dump(
    {"data": {
        "type": "profiles",
        "attributes": {"name": sys.argv[2], "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": sys.argv[3]}},
            "certificates": {"data": [{"type": "certificates", "id": sys.argv[4]}]},
        },
    }},
    open(sys.argv[1], "w"),
)
PY
  api_call POST /v1/profiles "$WORK/profile-request.json"
  case "$API_STATUS" in
    200|201) ;;
    409)
      die "POST /v1/profiles returned 409 Conflict: a profile named '$PROFILE_NAME' already exists but is not bound to bundle id $BUNDLE_ID / certificate $CERT_RESOURCE_ID." \
          "Delete or rename it in the developer portal and re-run this job." \
          "$(response_snippet)"
      ;;
    403)
      die "The API key is not allowed to create profiles (HTTP 403). It needs the App Manager or Admin role." \
          "$(response_snippet)"
      ;;
    *)
      die "POST /v1/profiles failed (HTTP $API_STATUS)." "$(response_snippet)"
      ;;
  esac
  PROFILE_RESOURCE_ID="$(json_path "$API_BODY" data.id)"
  [ -n "$PROFILE_RESOURCE_ID" ] || die "POST /v1/profiles returned no resource id." "$(response_snippet)"
  json_path "$API_BODY" data.attributes.profileContent >"$WORK/profile.b64"
  profile_content_file="$WORK/profile.b64"
  info "Created profile '$PROFILE_NAME' (resource $PROFILE_RESOURCE_ID)."
fi

[ -s "$profile_content_file" ] || die "The App Store Connect API returned an empty profileContent."
b64decode "$profile_content_file" "$WORK/profile.mobileprovision"

security cms -D -i "$WORK/profile.mobileprovision" >"$WORK/profile.plist" 2>/dev/null \
  || die "The downloaded profile is not a CMS-signed .mobileprovision."
profile_uuid="$(plutil -extract UUID raw -o - "$WORK/profile.plist" 2>/dev/null || true)"
if [ -z "$profile_uuid" ]; then
  profile_uuid="$(python3 - "$WORK/profile.plist" <<'PY'
import plistlib, sys
print(plistlib.load(open(sys.argv[1], "rb")).get("UUID", ""))
PY
)"
fi
[ -n "$profile_uuid" ] || die "The downloaded profile has no UUID; refusing to install it."
profile_expiry="$(plutil -extract ExpirationDate raw -o - "$WORK/profile.plist" 2>/dev/null || true)"

# The app's entitlements require Sign in with Apple; a profile generated before
# the capability landed would not carry it. Warn early rather than let the
# archive fail on an opaque codesign error.
if ! python3 - "$WORK/profile.plist" <<'PY'
import plistlib, sys
entitlements = plistlib.load(open(sys.argv[1], "rb")).get("Entitlements") or {}
sys.exit(0 if "com.apple.developer.applesignin" in entitlements else 1)
PY
then
  warn "The profile does not list com.apple.developer.applesignin. If the capability POST was just enabled, re-run the job; otherwise the archive signing step will fail."
fi

profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profiles_dir"
cp "$WORK/profile.mobileprovision" "$profiles_dir/${profile_uuid}.mobileprovision"
info "Installed App Store profile '$PROFILE_NAME' (UUID $profile_uuid, expires ${profile_expiry:-unknown})."

# --- 4. Hand the values the archive/export steps need ----------------------

{
  echo "PROFILE_NAME=$PROFILE_NAME"
  echo "SIGNING_KEYCHAIN_PATH=$KEYCHAIN"
} >>"$GITHUB_ENV"

{
  echo "### Signing material provisioned via ASC API"
  echo ""
  echo "- App ID: \`$BUNDLE_ID\` (resource \`$BUNDLE_RESOURCE_ID\`, Sign in with Apple enabled)"
  echo "- Certificate: Apple Distribution \`$CERT_RESOURCE_ID\` (expires ${cert_expiry:-unknown})"
  echo "- Profile: \`$PROFILE_NAME\` \`$PROFILE_RESOURCE_ID\` (UUID \`$profile_uuid\`, expires ${profile_expiry:-unknown})"
  echo "- Signing is manual: \`CODE_SIGN_IDENTITY=\"Apple Distribution\"\`, \`PROVISIONING_PROFILE_SPECIFIER=\"$PROFILE_NAME\"\`"
  echo ""
  echo "The certificate private key and the .p12 password exist only on this runner."
} >>"$GITHUB_STEP_SUMMARY"

info "Signing material ready: identity 'Apple Distribution', profile '$PROFILE_NAME'."
