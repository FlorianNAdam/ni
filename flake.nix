{
  description = "Mirage FUSE filesystem with configurable file content";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    bundle = {
      url = "github:FlorianNAdam/bundle";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    {
      nixosModules.ni =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        let
          inherit (lib)
            types
            mkOption
            mkEnableOption
            mkIf
            ;
        in
        let
          bundle = inputs.bundle.packages.${pkgs.system}.bundle;

          nixos-rebuild =
            operation: flags:
            pkgs.writeShellScript "nixos-wrapped-${operation}" (
              ''
                NIXOS_CONFIG="${config.ni.nixos.config}"         
                if [ -z "$NIXOS_CONFIG" ]; then
                  echo "You must specify the path to the NixOS config!"
                  exit 1
                fi

                NIXOS_HOST="${config.ni.nixos.host}"
                if [ -z "$NIXOS_HOST" ]; then
                  echo "You must specify a host for the NixOS config!"
                  exit 1
                fi

                set -e
                cd $NIXOS_CONFIG
                git add .
                sudo true
              ''
              + (
                let
                  base-command = ''sudo NIXOS_LABEL="$NIXOS_LABEL" nixos-rebuild ${operation} ${lib.concatStringsSep " " flags} --flake $NIXOS_CONFIG#$NIXOS_HOST'';
                in
                if config.ni.nom.enable then
                  "${base-command} |& ${pkgs.nix-output-monitor}/bin/nom"
                else
                  base-command
              )
            );

          rebuild = pkgs.writeShellScript "ni-rebuild" ''
            parser_definition() {
              setup REST help:usage -- "Usage: ni rebuild [options]... <message>" ' '
              msg -- 'Options:'
              param LABEL -l --label -- "Boot label for the generation (optional)"
              disp :usage --help -- "Show this help message"
            }

            eval "$(${pkgs.getoptions}/bin/getoptions parser_definition) exit 1"

            if [ $# -eq 0 ]; then
              echo "Error: message argument is required" >&2
              usage
              exit 1
            fi
            MESSAGE="$*"

            if [ -z "$LABEL" ]; then
              LABEL=$MESSAGE
            fi

            cd $NIXOS_CONFIG

            # add files to repo
            git add .

            # check if rebuild will work
            ${nixos-rebuild "dry-activate" [ ]}

            # sync git repo
            cd $NIXOS_CONFIG
            git commit -a --allow-empty -m "$MESSAGE"

            if git pull --rebase --dry-run; then
              git pull --rebase

              if git push --dry-run; then
                git push
              else
                echo "Can't push to remote. Skipping git push."
              fi
            else
              echo "Can't pull from remote. Skipping git sync"
            fi

            ${switch} --label "$LABEL" "$MESSAGE"
          '';

          update = pkgs.writeShellScript "ni-update" ''
            NIXOS_CONFIG="${config.ni.nixos.config}"         
            if [ -z "$NIXOS_CONFIG" ]; then
              echo "You must specify the path to the NixOS config!"
              exit 1
            fi
               
            cd $NIXOS_CONFIG
            nix flake update $@

            ${rebuild} "update $@"
          '';

          sync = pkgs.writeShellScript "ni-sync" ''
            NIXOS_CONFIG="${config.ni.nixos.config}"         
            if [ -z "$NIXOS_CONFIG" ]; then
              echo "You must specify the path to the NixOS config!"
              exit 1
            fi
               
            cd $NIXOS_CONFIG
            git add .
            before_hash=$(git rev-parse HEAD)
            git pull --rebase
            after_hash=$(git rev-parse HEAD)

            if [ "$before_hash" != "$after_hash" ]; then
              echo "Changes were pulled and applied."

              ${switch} "sync"
            else
              echo "No changes were pulled."
            fi
          '';

          test = pkgs.writeShellScript "ni-test" ''
            ${nixos-rebuild "test" [ ]}
          '';

          switch = pkgs.writeShellScript "ni-switch" ''
            parser_definition() {
              setup REST help:usage -- "Usage: ni switch [options]... <message>" ' '
              msg -- 'Options:'
              param LABEL -l --label -- "Boot label for the generation (optional)"
              disp :usage --help -- "Show this help message"
            }

            # Label sanitization function
            sanitize_label() {
              local input="$1"
              input="''${input// /_}"
              input="''${input//[^a-zA-Z0-9:_._-]/}"
              echo "$input"
            }

            eval "$(${pkgs.getoptions}/bin/getoptions parser_definition) exit 1"

            if [ $# -eq 0 ]; then
              echo "Error: message argument is required" >&2
              usage
              exit 1
            fi
            MESSAGE="$*"

            if [ -z "$LABEL" ]; then
              LABEL=$MESSAGE
            fi
            LABEL=$(sanitize_label "$LABEL")

            NIXOS_LABEL="$LABEL" ${nixos-rebuild "switch" [ "--impure" ]}
          '';

          clean = pkgs.writeShellScript "ni-clean" ''
            sudo nix-collect-garbage -d
            nix-collect-garbage -d
            sudo /run/current-system/bin/switch-to-configuration boot
          '';

          commands = [
            {
              name = "rebuild";
              executable = rebuild;
              description = "Rebuilds the NixOS environment";
            }
            {
              name = "update";
              executable = update;
              description = "Updates the system flake inputs and rebuilds";
            }
            {
              name = "sync";
              executable = sync;
              description = "Syncs system configuration with remote repository";
            }
            {
              name = "test";
              executable = test;
              description = "Tests the configuration without applying changes";
            }
            {
              name = "switch";
              executable = switch;
              description = "Switches to the new system generation";
            }
            {
              name = "clean";
              executable = clean;
              description = "Cleans up old system generations and temporary files";
            }
          ];

          commandsString = lib.concatStringsSep " " (
            lib.map (
              {
                name,
                executable,
                description ? "",
              }:
              let
                nameString = if name != "" then "${name}" else throw "Command name cannot be empty";
                executableString =
                  if executable != "" then ":${executable}" else throw "Command executable cannot be empty";
                descriptionString = lib.optionalString (description != "") ":${description}";
              in
              "\\\n    --command ${
                lib.escapeShellArg (
                  lib.concatStrings [
                    nameString
                    executableString
                    descriptionString
                  ]
                )
              }"
            ) commands
          );

          ni = pkgs.writeShellScriptBin "ni" ''
            ${bundle}/bin/bundle \
                --name ni ${commandsString} \
                -- "$@"
          '';
        in
        {
          options.ni = {
            enable = mkEnableOption "Enable the ni program";

            nixos = {
              config = mkOption {
                type = types.str;
              };

              host = mkOption {
                type = types.str;
              };
            };

            nom = {
              enable = lib.mkEnableOption "Enable pretty printing with nom";
            };
          };

          config = mkIf config.ni.enable {
            environment.systemPackages = [ ni ];
          };
        };
    };
}
