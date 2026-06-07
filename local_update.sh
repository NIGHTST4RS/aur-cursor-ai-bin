#!/bin/bash
# Interactive local updater for the cursor-ai-bin package recipe.

set -euo pipefail

PKGNAME="cursor-ai-bin"
TEMPLATE="PKGBUILD.sed"
GENERATED="PKGBUILD.test"
CURSOR_UPDATE_API="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local reply suffix

    case "$default" in
        y|Y) suffix="Y/n" ;;
        *) suffix="y/N" ;;
    esac

    read -r -p "${prompt} (${suffix}) " reply
    if [[ -z "$reply" ]]; then
        reply="$default"
    fi
    [[ "$reply" =~ ^[Yy]$ ]]
}

require_command() {
    local missing=0

    echo "Checking dependencies..."
    for cmd in curl jq sha512sum sed grep awk sort; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            echo "Missing required command: $cmd"
            missing=1
        fi
    done

    if [[ "$missing" -eq 1 ]]; then
        exit 1
    fi
}

extract_commit() {
    echo "$1" | sed -n 's|.*/production/\([^/]*\).*|\1|p'
}

version_lt() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" && "$1" != "$2" ]]
}

select_candidate() {
    local source="$1"
    local payload="$2"
    local candidate_pkgver candidate_commit candidate_deb_url

    candidate_pkgver=$(echo "$payload" | jq -r '.version // empty')
    candidate_commit=$(echo "$payload" | jq -r '.commitSha // empty')
    candidate_deb_url=$(echo "$payload" | jq -r '.debUrl // empty')

    if [[ -z "$candidate_commit" && -n "$candidate_deb_url" ]]; then
        candidate_commit=$(extract_commit "$candidate_deb_url")
    fi

    if [[ -z "$candidate_pkgver" || -z "$candidate_commit" || -z "$candidate_deb_url" ]]; then
        echo "Skipping ${source} candidate due to incomplete metadata"
        return
    fi
    if ! [[ "$candidate_pkgver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Skipping ${source} candidate due to invalid version format: ${candidate_pkgver}"
        return
    fi
    if ! [[ "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
        echo "Skipping ${source} candidate due to invalid commit format: ${candidate_commit}"
        return
    fi

    if [[ -z "${NEW_PKGVER:-}" ]] || version_lt "$NEW_PKGVER" "$candidate_pkgver"; then
        NEW_PKGVER="$candidate_pkgver"
        NEW_COMMIT="$candidate_commit"
        DEB_URL="$candidate_deb_url"
        SELECTED_SOURCE="$source"
    fi
}

query_golden_minor() {
    local minor="$1"
    local golden_response

    [[ -n "$minor" ]] || return
    golden_response=$(curl -fsSL --retry 2 --retry-delay 2 --retry-connrefused --connect-timeout 10 --max-time 30 "https://api2.cursor.sh/updates/api/download/golden/linux-x64-deb/cursor/${minor}" || true)
    if [[ -n "$golden_response" ]]; then
        select_candidate "golden/${minor}" "$golden_response"
    else
        echo "Golden API unavailable for ${minor}; continuing."
    fi
}

current_pkgbuild_value() {
    local key="$1"
    if [[ -f PKGBUILD ]]; then
        grep -E "^${key}=" PKGBUILD | cut -d= -f2 | sed 's/ #.*//' || true
    fi
}

installed_pkgver() {
    if command -v pacman > /dev/null 2>&1 && pacman -Q "$PKGNAME" > /dev/null 2>&1; then
        pacman -Q "$PKGNAME" | awk '{print $2}' | sed 's/-[^-]*$//'
    fi
}

generate_pkgbuild() {
    local sha="$1"

    awk -v pkgver="$NEW_PKGVER" \
        -v commit="$NEW_COMMIT" \
        -v sha="$sha" \
        'BEGIN {OFS=""}
         /^pkgver=/ {print "pkgver=" pkgver; next}
         /^_commit=/ {print "_commit=" commit " # sed'\''ded at GitHub WF"; next}
         /^sha512sums\[0\]=/ {print "sha512sums[0]=" sha; next}
         {print}' "$TEMPLATE" > "$GENERATED"
}

validate_pkgbuild() {
    local sha="$1"
    local failed=0

    echo "Validating ${GENERATED}..."

    if ! grep -q "^pkgver=${NEW_PKGVER}$" "$GENERATED"; then
        echo "pkgver was not set correctly"
        failed=1
    fi
    if ! grep -q "^_commit=${NEW_COMMIT}" "$GENERATED"; then
        echo "_commit was not set correctly"
        failed=1
    fi
    if ! grep -q "^sha512sums\[0\]=${sha}" "$GENERATED"; then
        echo "sha512sums[0] was not set correctly"
        failed=1
    fi
    if ! grep -q "^install=cursor-ai-bin.install$" "$GENERATED"; then
        echo "install script hook is missing"
        failed=1
    fi
    if ! grep -q "ripgrep" "$GENERATED"; then
        echo "ripgrep dependency is missing"
        failed=1
    fi

    if [[ "$failed" -eq 1 ]]; then
        echo "Validation failed."
        exit 1
    fi

    echo "Validation passed."
}

clean_artifacts() {
    local artifacts=()
    shopt -s nullglob
    [[ -e pkg ]] && artifacts+=(pkg)
    [[ -e src ]] && artifacts+=(src)
    artifacts+=(cursor_*.deb)
    artifacts+=(cursor-ai-bin-*.pkg.tar.*)
    artifacts+=(*.src.tar.*)
    artifacts+=(PKGBUILD.backup)
    shopt -u nullglob

    if [[ "${#artifacts[@]}" -eq 0 ]]; then
        echo "No build artifacts found."
        return
    fi

    echo "Build artifacts:"
    printf '  %s\n' "${artifacts[@]}"

    if prompt_yes_no "Delete these artifacts?" n; then
        rm -rf -- "${artifacts[@]}"
        echo "Artifacts deleted."
    else
        echo "Artifacts kept."
    fi
}

main() {
    local current_pkgver current_commit installed_version stable_pkgver stable_minor current_minor
    local api_response tmp_deb new_sha

    echo "Cursor local package updater"
    echo "============================"
    echo

    require_command

    if [[ ! -f "$TEMPLATE" ]]; then
        echo "${TEMPLATE} not found."
        exit 1
    fi

    installed_version=$(installed_pkgver)
    if [[ -n "$installed_version" ]]; then
        echo "Installed package version: ${installed_version}"
    else
        echo "Installed package version: not found via pacman"
    fi

    current_pkgver=$(current_pkgbuild_value pkgver)
    current_commit=$(current_pkgbuild_value _commit)
    echo "Current PKGBUILD version: ${current_pkgver:-none}"
    echo "Current PKGBUILD commit: ${current_commit:-none}"
    echo

    echo "Fetching latest Cursor release metadata..."
    api_response=$(curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 10 --max-time 30 "$CURSOR_UPDATE_API")
    if [[ -z "$api_response" ]]; then
        echo "Cursor update API returned an empty response."
        exit 1
    fi

    NEW_PKGVER=""
    NEW_COMMIT=""
    DEB_URL=""
    SELECTED_SOURCE=""

    select_candidate stable "$api_response"
    stable_pkgver=$(echo "$api_response" | jq -r '.version // empty')
    stable_minor=$(echo "$stable_pkgver" | awk -F. 'NF>=2 {print $1 "." $2}')
    current_minor=$(echo "${current_pkgver:-}" | awk -F. 'NF>=2 {print $1 "." $2}')

    query_golden_minor "$current_minor"
    if [[ "$stable_minor" != "$current_minor" ]]; then
        query_golden_minor "$stable_minor"
    fi

    if [[ -z "$NEW_PKGVER" || -z "$NEW_COMMIT" || -z "$DEB_URL" ]]; then
        echo "Could not resolve a complete Cursor release candidate."
        exit 1
    fi

    echo "Latest candidate: ${NEW_PKGVER} (${SELECTED_SOURCE})"
    echo "Candidate commit: ${NEW_COMMIT}"
    echo

    if [[ -n "$current_pkgver" ]] && version_lt "$NEW_PKGVER" "$current_pkgver"; then
        echo "Refusing downgrade from ${current_pkgver} to ${NEW_PKGVER}."
        clean_artifacts
        exit 0
    fi

    if [[ "$current_pkgver" == "$NEW_PKGVER" && "$current_commit" == "$NEW_COMMIT" ]]; then
        echo "PKGBUILD already matches the latest candidate."
        if [[ -n "$installed_version" && "$installed_version" != "$NEW_PKGVER" ]]; then
            echo "Installed package is ${installed_version}, so a local install can still update this PC."
        else
            clean_artifacts
            exit 0
        fi
    else
        if ! prompt_yes_no "Download the upstream .deb and generate ${GENERATED}?" y; then
            clean_artifacts
            exit 0
        fi

        tmp_deb=$(mktemp /tmp/cursor_local_update.XXXXXX.deb)
        trap 'rm -f "$tmp_deb"' EXIT

        echo "Downloading ${DEB_URL}..."
        curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 15 --max-time 300 "$DEB_URL" -o "$tmp_deb"
        if [[ ! -s "$tmp_deb" ]]; then
            echo "Downloaded .deb is empty."
            exit 1
        fi

        new_sha=$(sha512sum "$tmp_deb" | cut -d ' ' -f 1)
        echo "SHA512: ${new_sha:0:20}..."

        generate_pkgbuild "$new_sha"
        validate_pkgbuild "$new_sha"
        echo

        if prompt_yes_no "Show the generated PKGBUILD?" n; then
            cat "$GENERATED"
            echo
        fi

        if [[ -f PKGBUILD ]] && prompt_yes_no "Show diff against current PKGBUILD?" y; then
            diff -u PKGBUILD "$GENERATED" || true
            echo
        fi

        if ! prompt_yes_no "Replace PKGBUILD with ${GENERATED}?" n; then
            echo "Kept ${GENERATED}; PKGBUILD was not changed."
            clean_artifacts
            exit 0
        fi

        cp "$GENERATED" PKGBUILD
        echo "Updated PKGBUILD."
    fi

    if ! command -v makepkg > /dev/null 2>&1; then
        echo "makepkg was not found; skipping local install prompt."
        clean_artifacts
        exit 0
    fi

    if prompt_yes_no "Check sources with makepkg --verifysource before installing?" y; then
        makepkg --verifysource --noconfirm -f
    fi

    if prompt_yes_no "Build and install ${PKGNAME} with makepkg -si?" n; then
        makepkg -si
    else
        echo "Skipped local install."
    fi

    clean_artifacts
    echo "Done."
}

main "$@"
