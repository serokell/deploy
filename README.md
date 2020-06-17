# Deploy

**THIS IS CURRENTLY WIP, AND PROBABLY DOES NOT WORK AT ALL**

## Idea

`deploy.sh` is a simple script that parses a flake passed to it. It expects the following outputs:

```
deploy
|--(optional)user # ssh user
|--nodes
   |--<NODE>
      |--(optional)user
      |--hostname # hostname of node
      |--profiles
         |--<PROFILE>
            |--(optional)user
            |--(optional)profileUser # user that owns the profile; will be set to $user if omitted
            |--(optional)activate # activation script to run after installing the profile; will be ran as $profileUser; no activation if omitted
            |--path # path that should be linked to profile
         |--<PROFILE>...
   |--<NODE>...

```

This structure is subject to change a lot during initial development.

## Usage

`nix run github:serokell/deploy your-flake#node.profile`
