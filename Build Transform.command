#!/bin/bash
# Double-click this file in Finder to build Transform and create an unsigned
# .ipa for Signulous. The build never modifies Git history or the repository.

export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")" || exit 1

finish() {
    echo
    echo "──────────────────────────────────────────────"
    read -n 1 -s -r -p "Press any key to close this window."
    echo
    exit "${1:-0}"
}

commits() {
    if [ "$1" = "1" ]; then
        echo "1 change"
    else
        echo "$1 changes"
    fi
}

[ -t 1 ] && printf '\033c'
echo "Transform — build an .ipa for Signulous"
echo "──────────────────────────────────────────────"
echo

case "$(xcode-select -p 2>/dev/null)" in
    *Xcode.app*)
        echo "✓ Xcode"
        ;;
    *)
        echo "✗ Xcode is not the active developer directory. No IPA was built."
        echo
        echo "  Open Terminal, paste this line, press Enter, and enter your Mac password:"
        echo
        echo "    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
        echo
        echo "  Then double-click this file again."
        finish 1
        ;;
esac

# A stale build can look current while silently omitting fixes. The fetch is
# deliberately non-fatal: GitHub Desktop owns private-repository credentials,
# but it writes its downloaded origin ref into this checkout.
echo
echo "→ Checking GitHub"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "✗ This repository is not on a branch. No IPA was built."
    echo "  Open Transform in GitHub Desktop and switch to a branch first."
    echo "  Local changes are untouched."
    finish 1
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "✗ This copy has changes that are not committed. No IPA was built."
    echo
    echo "  Building now would produce an app containing work that is not on GitHub."
    echo "  Commit or discard the changes in GitHub Desktop, then run this again."
    echo "  Local changes are untouched."
    finish 1
fi

if GIT_TERMINAL_PROMPT=0 git fetch origin "$branch" >/dev/null 2>&1; then
    against="GitHub"
else
    against="what GitHub Desktop last downloaded"
    echo "! This window cannot sign in to GitHub, so it is comparing against"
    echo "  $against instead."
    echo "  That is expected. Clicking \"Pull origin\" in GitHub Desktop before"
    echo "  building keeps this check accurate."
fi

counts="$(git rev-list --left-right --count "HEAD...origin/$branch" 2>/dev/null)"
set -- $counts
ahead="$1"
behind="$2"

if [ -z "$counts" ] || [ -z "$ahead" ] || [ -z "$behind" ] ||
   ! [[ "$ahead" =~ ^[0-9]+$ ]] || ! [[ "$behind" =~ ^[0-9]+$ ]]; then
    echo "✗ Could not compare this copy with GitHub at all. No IPA was built."
    echo "  Open Transform in GitHub Desktop and click \"Pull origin\", then run"
    echo "  this file again. Local changes are untouched."
    finish 1
fi

if [ "$behind" != "0" ]; then
    echo "✗ This copy is missing $(commits "$behind") from $against. No IPA was built."
    echo
    echo "  Building now would rebuild an older app and look like the newest one."
    echo "  Open Transform in GitHub Desktop and click \"Pull origin\", then run"
    echo "  this file again. Local changes are untouched."
    finish 1
fi

if [ "$ahead" != "0" ]; then
    echo "✗ This copy has $(commits "$ahead") that $against does not. No IPA was built."
    echo
    echo "  Open Transform in GitHub Desktop and click \"Push origin\", then run"
    echo "  this file again. Local changes are untouched."
    finish 1
fi

echo "✓ Up to date with $against ($branch)"
if [ "$against" != "GitHub" ]; then
    newest="$(git log -1 --format='%s (%cr)' "origin/$branch" 2>/dev/null)"
    [ -n "$newest" ] && echo "  Newest change it knows about: $newest"
fi

echo
echo "→ Finding the Xcode project"
workspace="$(find . -maxdepth 4 -name '*.xcworkspace' -not -path '*/.git/*' -not -path '*.xcodeproj/*' -print 2>/dev/null | head -n 1)"
project="$(find . -maxdepth 4 -name '*.xcodeproj' -not -path '*/.git/*' -print 2>/dev/null | head -n 1)"

if [ -n "$workspace" ]; then
    container_flag="-workspace"
    container="$workspace"
elif [ -n "$project" ]; then
    container_flag="-project"
    container="$project"
else
    echo "✗ No Xcode project or workspace was found. No IPA was built."
    echo "  This repository may be incomplete. Open it in GitHub Desktop and click"
    echo "  \"Pull origin\", then try this file again."
    finish 1
fi
echo "✓ $(basename "$container")"

schemes_json="$(xcodebuild -list -json "$container_flag" "$container" 2>/dev/null)"
schemes=()
while IFS= read -r line; do
    [ -n "$line" ] && schemes+=("$line")
done < <(printf '%s' "$schemes_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
container = data.get("workspace") or data.get("project") or {}
for name in container.get("schemes", []):
    print(name)
' 2>/dev/null)

if [ "${#schemes[@]}" -eq 0 ]; then
    echo "✗ No shared scheme was found. No IPA was built."
    echo
    echo "  Open the project in Xcode, choose Product ▸ Scheme ▸ Manage Schemes,"
    echo "  tick \"Shared\" for Transform's app scheme, then commit and push that"
    echo "  change in GitHub Desktop."
    finish 1
fi

if [ "${#schemes[@]}" -eq 1 ]; then
    scheme="${schemes[0]}"
    echo "✓ Scheme: $scheme"
else
    echo
    echo "This project has several schemes:"
    echo
    index=1
    for name in "${schemes[@]}"; do
        printf '  %d) %s\n' "$index" "$name"
        index=$((index + 1))
    done
    echo
    read -r -p "Which one builds the iPhone app? [1] " choice
    choice="${choice:-1}"
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#schemes[@]}" ]; then
        echo "✗ That is not one of the numbers above. No IPA was built."
        finish 1
    fi
    scheme="${schemes[$((choice - 1))]}"
fi

# Generated data stays outside the checkout so the next run remains clean.
derived="$HOME/Library/Caches/TransformBuild"
log="$derived/last-build.log"
mkdir -p "$derived"

echo
echo "→ Building $scheme, unsigned. This takes a few minutes."
printf '  '
xcodebuild \
    "$container_flag" "$container" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build > "$log" 2>&1 &
build_pid=$!
while kill -0 "$build_pid" 2>/dev/null; do
    printf '.'
    sleep 5
done
wait "$build_pid"
build_status=$?
echo
echo

products="$derived/Build/Products/Release-iphoneos"
built_app="$(find "$products" -maxdepth 1 -name '*.app' -print 2>/dev/null | head -n 1)"
if [ "$build_status" -ne 0 ] || [ -z "$built_app" ]; then
    echo "✗ The build failed. No IPA was built. The last lines of the log were:"
    echo "──────────────────────────────────────────────"
    [ -f "$log" ] && tail -n 40 "$log"
    echo "──────────────────────────────────────────────"
    echo
    echo "Full log: $log"
    echo "Send that file to Codex and it can explain the problem."
    finish 1
fi

app_name="$(basename "$built_app" .app)"
echo "✓ Built $app_name.app"

echo
echo "→ Packaging $app_name.ipa"
staging="$derived/package"
rm -rf "$staging"
mkdir -p "$staging/Payload"
if ! cp -R "$built_app" "$staging/Payload/" ||
   ! (cd "$staging" && zip -qry "$app_name.ipa" Payload); then
    echo "✗ The app was built, but its IPA could not be packaged."
    echo "  The built app is still available here: $built_app"
    finish 1
fi

dropoff="$HOME/Desktop/Singulous Files"
if [ ! -d "$dropoff" ] && [ -d "$HOME/Desktop/Signulous Files" ]; then
    dropoff="$HOME/Desktop/Signulous Files"
fi

echo
echo "→ Copying to the Desktop"
if mkdir -p "$dropoff" 2>/dev/null &&
   cp "$staging/$app_name.ipa" "$dropoff/.$app_name.ipa.partial" 2>/dev/null &&
   mv "$dropoff/.$app_name.ipa.partial" "$dropoff/$app_name.ipa" 2>/dev/null; then
    rm -f "$dropoff/.$app_name.ipa.partial"
    echo "✓ Done"
    echo
    echo "  $dropoff/$app_name.ipa"
    echo
    echo "Each build replaces only Transform's IPA. Your other files are untouched."
    echo "A Finder window is opening with it selected."
    open -R "$dropoff/$app_name.ipa"
    finish 0
fi

rm -f "$dropoff/.$app_name.ipa.partial"
echo "! The build worked, but it could not be copied to the Desktop folder."
echo "  Use this IPA instead:"
echo
echo "  $staging/$app_name.ipa"
open -R "$staging/$app_name.ipa"
finish 0
