pkgs:
# We should probably create a flake that simplifies this

let
  service = pkgs.writeTextFile {
    name = "hello.service";
    text = ''
      [Install]
      WantedBy=default.target

      [Service]
      ExecStart=${pkgs.hello}/bin/hello
      Type=oneshot

      [Unit]
      Description=Hello world
    '';
  };
in pkgs.writeShellScriptBin "activate" ''
  mkdir -p $HOME/.config/systemd/user
  rm $HOME/.config/systemd/user/hello.service
  ln -s ${service} $HOME/.config/systemd/user/hello.service
  systemctl --user daemon-reload
  systemctl --user restart hello
''
