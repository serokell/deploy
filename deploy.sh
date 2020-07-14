#!/usr/bin/env nix-shell
#!nix-shell -p jq -i bash

# shellcheck shell=bash

set -euo pipefail


# For first deployment to bare server
if [[ ${1:-} == '--prime' ]]; then
    shift

    bare_server=1
else
    bare_server=0
fi

get() {
    set +u
    local from_env
    from_env="$(eval "echo \$$1")"
    set -u
    if [[ -n "$from_env" ]]; then
        echo "$from_env"
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

    local only_profile="del(.path) | del(.activate)"
    local merged
    merged="$(NODE="$NODE" PROFILE="$PROFILE" jq "(. | del(.nodes) | del(.hostname) | $only_profile) \
                      + (.nodes[env.NODE] | del(.profiles) | $only_profile) \
                      + (.nodes[env.NODE].profiles[env.PROFILE] | del(.hostname))" <<< "$JSON")"

    host="$(get hostname <<< "$merged")"
    ssh_user="$(get sshUser <<< "$merged")"
    profile_user="$(get user <<< "$merged")"
    closure="$(get path <<< "$merged")"
    activate="$(get activate <<< "$merged")"
    fast_connection="$(get fastConnection <<< "$merged")"
    extra_ssh_opts="$(get sshOpts <<< "$merged")"
    bootstrap="$(get bootstrap <<< "$merged")"
    auto_rollback="$(get autoRollback <<< "$merged")"

    ensure_set host hostname
    ensure_set closure path

    if [[ "$extra_ssh_opts" == null ]]; then
        extra_ssh_opts=""
    fi

    export NIX_SSHOPTS="${extra_ssh_opts}"

    SUDO=""


    if [[ "$ssh_user" == null ]]; then
        if [[ "$profile_user" == null ]]; then
            echo "neither user nor sshUser set for profile $PROFILE of node $NODE"
            exit 1
        fi
        ssh_user="$USER"

    fi
    if [[ ! "$profile_user" == null ]] && [[ ! "$profile_user" == "$ssh_user" ]]; then
        SUDO="sudo -u $profile_user"
    fi

    if [[ "$profile_user" == null ]]; then
        profile_user="$ssh_user"
    fi

    local profile_path

    if [[ "$profile_user" == root ]]; then
        profile_path="/nix/var/nix/profiles/$PROFILE"
    else
        profile_path="/nix/var/nix/profiles/per-user/$profile_user/$PROFILE"
    fi

    if [[ "$flake_support" == 1 ]]; then
        nix build --no-link "$REPO#deploy.nodes.$NODE.profiles.$PROFILE.path"
    else
        nix-build "$REPO" -A "deploy.nodes.$NODE.profiles.$PROFILE.path" --no-out-link
    fi

    if [[ -n ${LOCAL_KEY:-} ]]; then
        nix sign-paths -r -k "$LOCAL_KEY" "$closure"
    fi

    if [[ "$activate" == null ]]; then
        activate=true
    fi

    if [[ "$bootstrap" == null ]]; then
        bootstrap=true
    fi

    EXTRA_NIX_COPY_OPTS=""

    if [[ ! "$fast_connection" == true ]]; then
        EXTRA_NIX_COPY_OPTS="$EXTRA_NIX_COPY_OPTS --substitute-on-destination"
    fi

    set -x

    # shellcheck disable=SC2086
    nix copy $EXTRA_NIX_COPY_OPTS --no-check-sigs --to "ssh://$ssh_user@$host" "$closure"

    # shellcheck disable=SC2029
    # shellcheck disable=SC2087
    # shellcheck disable=SC2086
    ssh $NIX_SSHOPTS "$ssh_user@$host" <<EOF
set -euo pipefail
export PROFILE="$profile_path"
if [[ ! -e "$profile_path" ]] && [[ "$bootstrap" != null ]]; then
    echo "Bootstrapping"
    DO_bootstrap=1
else
    DO_bootstrap=0
fi
$SUDO nix-env -p "$profile_path" --set "$closure"
if [[ "\$DO_bootstrap" -eq 1 ]]; then
   eval "set -x; $SUDO $bootstrap; set +x" || {
        rm "$profile_path"
        exit 1
   }
fi
set -x
eval "$SUDO $activate" || {
   if [[ "$auto_rollback" == true ]]; then
      $SUDO nix-env -p "$profile_path" --rollback
      BROKEN="\$($SUDO nix-env -p "$profile_path" --list-generations | tail -1 | cut -d" " -f3)"
      $SUDO nix-env -p "$profile_path" --delete-generations "\$BROKEN"
      # Assuming that activation command didn't change
      eval "$SUDO $activate"
   fi
   exit 1
}
EOF
    set +x
}

deploy_all_profiles() {
    if [[ "$bare_server" == 1 ]]; then
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
    flake_support=1
    JSON="$(nix eval --json "$REPO"#deploy "$@")"
else
    flake_support=0
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
