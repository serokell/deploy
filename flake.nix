{
  description = "Deploy flakes";

  outputs = { self, nixpkgs }: {

    defaultApp = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" ] (_: {
      type = "app";
      program = toString ./deploy.sh;
    });
    checks = builtins.mapAttrs (_: pkgs:
      {
        shellcheck = pkgs.runCommandNoCC "shellcheck-deploy" { }
          "${pkgs.shellcheck}/bin/shellcheck ${./deploy.sh}; touch $out";
      }) nixpkgs.legacyPackages;
  };
}
