{
  description = "peersight development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
          }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            go_1_26
            nodejs
            git
            gnumake
            wireguard-tools
            docker-compose
            postgresql
          ];

          shellHook = ''
            export CGO_ENABLED=0
            export GOCACHE="${TMPDIR:-/tmp}/peersight-go-build-cache"
            export GOMODCACHE="${TMPDIR:-/tmp}/peersight-go-mod-cache"
          '';
        };
      });
    };
}
