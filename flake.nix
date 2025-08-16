{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    naersk = {
      url = "github:nix-community/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      flake-utils,
      naersk,
      nixpkgs,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = (import nixpkgs) {
          inherit system;
        };

        naersk-lib = pkgs.callPackage naersk { };

        ni = naersk-lib.buildPackage {
          src = ./.;

          preBuild = ''
            mkdir -p $out/bin
            ln -s ${./scripts} $out/scripts
          '';
        };
      in
      {
        packages = {
          inherit ni;
        };

        defaultPackage = self.packages.${system}.ni;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo
            rustc
          ];

          packages = with pkgs; [
            rust-analyzer
          ];
        };
      }
    );
}
