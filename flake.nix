{
  description = "Sakaar - a local, libvirt-native cyber range (graphical Kali + VulnHub target spinner)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      pkgsFor = system: import nixpkgs { inherit system; };

      # Userspace CLIs the range drives. KVM/libvirtd is a host prerequisite,
      # detected by `task doctor`, not provided here.
      devTools =
        pkgs: with pkgs; [
          go-task
          virt-manager # GUI + virt-install
          virt-viewer
          libvirt # virsh
          qemu # qemu-img
          p7zip
          jq
          yq-go
          fzf
          curl
          git
          openssh
          coreutils
          util-linux
          gnugrep
          gawk
          shellcheck
          shfmt
          yamllint
          nixfmt
          statix
          deadnix
        ];
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      devShells = forAllSystems (system: {
        default =
          let
            pkgs = pkgsFor system;
          in
          pkgs.mkShell {
            packages = devTools pkgs;
            shellHook = ''
              export SAKAAR_ROOT="$PWD"
              export LIBVIRT_DEFAULT_URI="qemu:///system"
              echo "sakaar :: nix develop ready. Run 'task' for the command list."
            '';
          };
      });

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          shellcheck = pkgs.runCommand "sakaar-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
            shellcheck ${self}/scripts/*.sh
            touch $out
          '';

          nixfmt = pkgs.runCommand "sakaar-nixfmt" { } ''
            ${pkgs.nixfmt}/bin/nixfmt --check ${self}/flake.nix
            touch $out
          '';

          yamllint = pkgs.runCommand "sakaar-yamllint" { } ''
            ${pkgs.yamllint}/bin/yamllint -c ${self}/.yamllint ${self}/config ${self}/catalog
            touch $out
          '';

          lint-nix =
            pkgs.runCommand "sakaar-lint-nix"
              {
                nativeBuildInputs = [
                  pkgs.statix
                  pkgs.deadnix
                ];
              }
              ''
                statix check ${self}/flake.nix
                deadnix --fail ${self}/flake.nix
                touch $out
              '';
        }
      );
    };
}
