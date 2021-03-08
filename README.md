# Deploy

⚠ **THIS REPOSITORY IS DEPRECATED IN FAVOR OF https://github.com/serokell/deploy-rs**

## TL;DR Usage

`nix run github:serokell/deploy your-flake#node.profile`

## Idea

`deploy.sh` is a simple script that parses a flake passed to it. You can find a description of what it exects in [interface](./interface)

To see example configurations, look in [examples folder](./examples).

This structure is subject to change a lot during initial development.

## Things to work on

- Ordered profiles
- Automatic rollbacks if one profile on node failed to deploy
- UI
