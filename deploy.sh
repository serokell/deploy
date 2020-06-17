#!/usr/bin/env nix-shell
#!nix-shell -p jq -i bash

# shellcheck shell=bash

set -euo pipefail

SSHOPTS=(-o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null')
export NIX_SSHOPTS="${SSHOPTS[*]}"

# For first deployment to bare server
if [[ ${1:-} == '--prime' ]]; then
    shift

    BARE_SERVER=1
else
    BARE_SERVER=0
fi

get() {
    jq -r ".$1" <<< "$MERGED"
}

not_set() {
    echo "$1 is not set for profile $PROFILE of node $NODE"
    exit 1
}

deploy_profile() {
    echo "=== Deploying profile $PROFILE of node $NODE ==="

    ONLY_PROFILE="del(.path) | del(.activate)"
    MERGED="$(jq "(. | del(.nodes) | del(.hostname) | $ONLY_PROFILE) + (.nodes.$NODE | del(.profiles) | $ONLY_PROFILE) + (.nodes.$NODE.profiles.$PROFILE | del(.hostname))" <<< "$JSON")"

    HOST="$(get hostname)"
    USER="$(get user)"
    PROFILE_USER="$(get profileUser)"
    CLOSURE="$(get path)"
    ACTIVATE="$(get activate)"

    if [[ "$USER" == null ]]; then
        not_set user
    fi

    if [[ ! "$PROFILE_USER" == null ]] && [[ ! "$PROFILE_USER" == "$USER" ]]; then
        SUDO="sudo -u $PROFILE_USER"
    else
        SUDO=""
    fi

    if [[ "$PROFILE_USER" == null ]]; then
        PROFILE_USER="$USER"
    fi

    if [[ "$PROFILE_USER" == root ]]; then
        PROFILE_PATH="/nix/var/nix/profiles/$PROFILE"
    else
        PROFILE_PATH="/nix/var/nix/profiles/per-user/$PROFILE_USER/$PROFILE"
    fi

    if [[ -n ${LOCAL_KEY:-} ]]; then
        nix sign-paths -r -k "$LOCAL_KEY" "$CLOSURE"
    fi

    if [[ "$BARE_SERVER" == 1 ]]; then
        echo "Checking if $HOST is up..."
        if ! timeout 5 ssh "${SSHOPTS[@]}" "$USER@$HOST" true; then
            echo "***** $HOST appears to be down *****"
            read -r -p "Enter a different hostname or an IP address for $NODE ($HOST)" HOST
        fi
    fi

    if [[ "$ACTIVATE" == null ]]; then
        ACTIVATE=true
    fi

    set -x

    nix copy --substitute-on-destination --to "ssh://$USER@$HOST" "$CLOSURE"

    # shellcheck disable=SC2029
    # shellcheck disable=SC2087
    ssh "${SSHOPTS[@]}" "$USER@$HOST" <<EOF
export PROFILE="$PROFILE_PATH"
if [[ "$BARE_SERVER" == 1 ]]; then
   mkdir -p "$(dirname "$PROFILE_PATH")"
fi
set -euox pipefail
$SUDO nix-env -p "$PROFILE_PATH" --set "$CLOSURE" && eval "$SUDO $ACTIVATE"
EOF
    set +x
}

deploy_all_profiles() {
    echo "==== Deploying all profiles of node $NODE ===="
    for PROFILE in $(jq -r ".nodes.$NODE.profiles | keys[]" <<< "$JSON"); do
        deploy_profile
    done
}

deploy_all_nodes() {
    echo "===== Deploying all nodes ====="
    for NODE in $(jq -r ".nodes | keys[]" <<< "$JSON"); do
        deploy_all_profiles
    done
}


if [[ -z ${1:-} ]]; then
    FLAKE=.
else
    FLAKE="$1"
    shift
fi


REPO="${FLAKE%#*}"

if grep "\#" <<< "$FLAKE" > /dev/null; then
    # foo#bar.baz -> bar.baz
    # foo#bar -> bar
    # foo ->
    FRAGMENT="${FLAKE#*#}"

    NODE="${FRAGMENT%.*}"
    if grep "\." <<< "$FRAGMENT" > /dev/null; then
        PROFILE="${FRAGMENT#*.}"
    fi
fi

JSON="$(nix eval --json "$REPO"#deploy "$@")"

if [[ -z ${NODE:-} ]]; then
    deploy_all_nodes
    exit 0
fi

if [[ -z ${PROFILE:-} ]]; then
    deploy_all_profiles
    exit 0
fi

deploy_profile

exit 0
