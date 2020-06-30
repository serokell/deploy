#!/usr/bin/env nix-shell
#!nix-shell -p jq -i bash

# shellcheck shell=bash

set -euo pipefail


# For first deployment to bare server
if [[ ${1:-} == '--prime' ]]; then
    shift

    BARE_SERVER=1
else
    BARE_SERVER=0
fi

get() {
    set +u
    FROM_ENV="$(eval "echo \$$1")"
    set -u
    if [[ ! -z "$FROM_ENV" ]]; then
        echo "$FROM_ENV"
    else
        jq -r ".$1"
    fi
}

ensure_set() {
    if [[ "$(eval "echo \$$1")" == null ]]; then
        echo "$2 is not set for profile $PROFILE of node $NODE"
        exit 1
    fi
}

deploy_profile() {
    echo "=== Deploying profile $PROFILE of node $NODE ==="

    ONLY_PROFILE="del(.path) | del(.activate)"
    MERGED="$(jq "(. | del(.nodes) | del(.hostname) | $ONLY_PROFILE) + (.nodes.\"$NODE\" | del(.profiles) | $ONLY_PROFILE) + (.nodes.\"$NODE\".profiles.\"$PROFILE\" | del(.hostname))" <<< "$JSON")"

    HOST="$(get hostname <<< "$MERGED")"
    SSH_USER="$(get sshUser <<< "$MERGED")"
    PROFILE_USER="$(get user <<< "$MERGED")"
    CLOSURE="$(get path <<< "$MERGED")"
    ACTIVATE="$(get activate <<< "$MERGED")"
    FAST_CONNECTION="$(get fastConnection <<< "$MERGED")"
    EXTRA_SSH_OPTS="$(get sshOpts <<< "$MERGED")"
    BOOTSTRAP="$(get bootstrap <<< "$MERGED")"
    AUTO_ROLLBACK="$(get autoRollback <<< "$MERGED")"

    ensure_set HOST hostname
    ensure_set CLOSURE path

    if [[ "$EXTRA_SSH_OPTS" == null ]]; then
        EXTRA_SSH_OPTS=""
    fi

    export NIX_SSHOPTS="${EXTRA_SSH_OPTS}"

    SUDO=""


    if [[ "$SSH_USER" == null ]]; then
        if [[ "$PROFILE_USER" == null ]]; then
            echo "neither user nor sshUser set for profile $PROFILE of node $NODE"
            exit 1
        fi
        SSH_USER="$USER"

    fi
    if [[ ! "$PROFILE_USER" == null ]] && [[ ! "$PROFILE_USER" == "$SSH_USER" ]]; then
        SUDO="sudo -u $PROFILE_USER"
    fi

    if [[ "$PROFILE_USER" == null ]]; then
        PROFILE_USER="$SSH_USER"
    fi


    if [[ "$PROFILE_USER" == root ]]; then
        PROFILE_PATH="/nix/var/nix/profiles/$PROFILE"
    else
        PROFILE_PATH="/nix/var/nix/profiles/per-user/$PROFILE_USER/$PROFILE"
    fi

    if [[ "$FLAKE_SUPPORT" == 1 ]]; then
        nix build --no-link "$REPO#deploy.nodes.$NODE.profiles.$PROFILE.path"
    else
        nix-build "$REPO" -A "deploy.nodes.$NODE.profiles.$PROFILE.path" --no-out-link
    fi

    if [[ -n ${LOCAL_KEY:-} ]]; then
        nix sign-paths -r -k "$LOCAL_KEY" "$CLOSURE"
    fi

    if [[ "$ACTIVATE" == null ]]; then
        ACTIVATE=true
    fi

    EXTRA_NIX_COPY_OPTS=""

    if [[ ! "$FAST_CONNECTION" == true ]]; then
        EXTRA_NIX_COPY_OPTS="$EXTRA_NIX_COPY_OPTS --substitute-on-destination"
    fi

    set -x

    # shellcheck disable=SC2086
    nix copy $EXTRA_NIX_COPY_OPTS --no-check-sigs --to "ssh://$SSH_USER@$HOST" "$CLOSURE"

    # shellcheck disable=SC2029
    # shellcheck disable=SC2087
    # shellcheck disable=SC2086
    ssh $NIX_SSHOPTS "$SSH_USER@$HOST" <<EOF
set -euo pipefail
export PROFILE="$PROFILE_PATH"
if [[ ! -e "$PROFILE_PATH" ]] && [[ -n "$BOOTSTRAP" ]]; then
    echo "Bootstrapping"
    DO_BOOTSTRAP=1
else
    DO_BOOTSTRAP=0
fi
$SUDO nix-env -p "$PROFILE_PATH" --set "$CLOSURE"
if [[ "\$DO_BOOTSTRAP" -eq 1 ]]; then
   eval "set -x; $SUDO $BOOTSTRAP; set +x"
fi
set -x
eval "$SUDO $ACTIVATE" || {
   if [[ "$AUTO_ROLLBACK" == true ]]; then
      $SUDO nix-env -p "$PROFILE_PATH" --rollback
      BROKEN="\$($SUDO nix-env -p "$PROFILE_PATH" --list-generations | tail -1 | cut -d" " -f1)"
      $SUDO nix-env -p "$PROFILE_PATH" --delete-generations "\$BROKEN"
      # Assuming that activation command didn't change
      eval "$SUDO $ACTIVATE"
   fi
}
EOF
    set +x
}

deploy_all_profiles() {
    if [[ "$BARE_SERVER" == 1 ]]; then
        echo "==== Bootstrapping node $NODE ===="

        PROFILE=system deploy_profile
    fi
    echo "==== Deploying all profiles of node $NODE ===="
    for PROFILE in $(jq -r ".nodes.\"$NODE\".profiles | keys[]" <<< "$JSON"); do
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


if nix eval --expr "builtins.getFlake" > /dev/null; then
    FLAKE_SUPPORT=1
    JSON="$(nix eval --json "$REPO"#deploy "$@")"
else
    FLAKE_SUPPORT=0
    JSON="$(nix-instantiate --strict --read-write-mode --json --eval -E "let r = import $REPO/.; in if builtins.isFunction r then (r {}).deploy else r.deploy")"
fi


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
