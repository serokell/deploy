{
  description = "Deploy GNU hello to localhost";

  outputs = { self, nixpkgs }: {
    deploy.nodes.example = {
      hostname = "localhost";
      profiles.hello = {
        user = "balsoft";
        path = nixpkgs.legacyPackages.x86_64-linux.hello;
        # Just to test that it's working
        activate = "$PROFILE/bin/hello";
      };
    };
  };
}
