#!/bin/bash
# Sign a development build with the existing wildcard profile, without increased-memory access.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${IPAD_APP_PATH:-DerivedData-iPad/Build/Products/Debug-iphoneos/iLightCraft.app}"
PROFILE="${IPAD_PROFILE_PATH:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/6ae52616-380a-4ff8-b0da-23072a13046d.mobileprovision}"
ENTITLEMENTS=$(mktemp -t lightcraft-entitlements)
trap 'rm -f "$ENTITLEMENTS"' EXIT
security cms -D -i "$PROFILE" > "$ENTITLEMENTS"
BUNDLE="${IPAD_BUNDLE_ID:-}"
[[ -n "$BUNDLE" ]] || BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
python3 - "$ENTITLEMENTS" "${APPLE_TEAM_ID:-D58RZM4K8N}" "$BUNDLE" <<'PY'
import plistlib,sys
path,team,bundle=sys.argv[1:]
with open(path,'rb') as f: profile=plistlib.load(f)
ent=profile['Entitlements']
identifier=f'{team}.{bundle}'
if ent.get('application-identifier') != f'{team}.*':
    raise SystemExit('The basic signing helper requires a wildcard profile for this team.')
ent['application-identifier']=identifier
ent['keychain-access-groups']=[identifier]
with open(path,'wb') as f: plistlib.dump(ent,f)
PY
/bin/cp -f "$PROFILE" "$APP/embedded.mobileprovision"
shopt -s nullglob
for LIBRARY in "$APP"/*.dylib; do
    codesign --force --sign "${IPAD_SIGNING_IDENTITY:-Apple Development: Christopher Wallace (46E4Y98628)}" "$LIBRARY"
done
codesign --force --sign "${IPAD_SIGNING_IDENTITY:-Apple Development: Christopher Wallace (46E4Y98628)}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"
