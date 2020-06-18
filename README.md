# Deploy

**THIS IS CURRENTLY WIP, AND PROBABLY DOES NOT WORK AT ALL**

## Idea

`deploy.sh` is a simple script that parses a flake passed to it. It expects the following outputs:

```
deploy
|--(optional)sshUser
|--nodes
   |--<NODE>
      |--(optional)sshUser
      |--hostname # hostname of node
      |--profiles
         |--<PROFILE>
            |--(optional)user # user that owns the profile; will be set to $sshUser if omitted
            |--(optional)sshUser
            |--(optional)activate # activation script to run after installing the profile; will be ran as $profileUser; no activation if omitted
            |--path # path that should be linked to profile
         |--<PROFILE>...
   |--<NODE>...

```

This structure is subject to change a lot during initial development.

## Usage

`nix run github:serokell/deploy your-flake#node.profile`

## Things to work on

- Ordered profiles
- Automatic rollbacks if one profile on node failed to deploy
- UI
