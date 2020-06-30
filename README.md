# Deploy

**THIS IS CURRENTLY WIP, AND PROBABLY DOES NOT WORK AT ALL**

## TL;DR Usage

`nix run github:serokell/deploy your-flake#node.profile`

## Idea

`deploy.sh` is a simple script that parses a flake passed to it. It expects the following outputs:

```
deploy
├── <generic args>
└── nodes
    ├── <NODE>
    │   ├── <generic args>
    │   ├── hostname
    │   └── profiles
    │       ├── <PROFILE>
    │       │   ├── <generic args>
    │       │   ├── activate
    │       │   ├── bootstrap
    │       │   └── path
    │       └── <PROFILE>...
    └── <NODE>...

```

Where `<generic args>` are all optional and can be one or multiple of:

- `sshUser` -- user to connect as
- `user` -- user to install and activate profiles with
- `sshOpts` -- options passed to `nix copy` and `ssh`
- `fastConnection` -- whether the connection from this host to the target one is fast (if it is, don't substitute on target and copy the entire closure) [default: `false`]
- `autoRollback` -- whether to roll back when the deployment fails [default: `false`]

For every profile of every node, arguments are merged with `<PROFILE>` taking precedence over `<NODE>` and `<NODE>` taking precedence over top-level.

You can also override values for all the profiles deployed by setting environment variables with the same names as the profile, for example `sshUser=foobar nix run github:serokell/deploy .` will connect to all nodes as `foobar@<NODE>.hostname`.

To see example configurations, look in [examples folder](./examples).

This structure is subject to change a lot during initial development.


## Things to work on

- Ordered profiles
- Automatic rollbacks if one profile on node failed to deploy
- UI
