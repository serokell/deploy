{
  description = "Deploy GNU hello to localhost";

  outputs = { self, nixpkgs }: {
    deploy.nodes.example = {
      hostname = "localhost";
      user = "balsoft";
      profiles.hello = {
        # Just to test that it's working
        activate = "$PROFILE/bin/hello";
        path = nixpkgs.legacyPackages.x86_64-linux.hello;
      };
    };
  };
}
