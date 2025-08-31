{
  description = "Mirage FUSE filesystem with configurable file content";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    clap-bash = {
      url = "github:FlorianNAdam/clap-bash";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      clap-bash,
      ...
    }:
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
          nixos-rebuild =
            operation: flags:
            pkgs.writeShellScript "nixos-wrapped-${operation}" ''
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
              ${
                let
                  base-command = ''sudo NIXOS_LABEL="$NIXOS_LABEL" nixos-rebuild ${operation} ${lib.concatStringsSep " " flags} --flake $NIXOS_CONFIG#$NIXOS_HOST'';
                in
                if config.ni.nom.enable then
                  "${base-command} |& ${pkgs.nix-output-monitor}/bin/nom"
                else
                  base-command
              }
            '';

          rebuild = pkgs.writeShellScript "ni-rebuild" ''
            NIXOS_CONFIG="${config.ni.nixos.config}"
            if [ -z "$NIXOS_CONFIG" ]; then
              echo "You must specify the path to the NixOS config!"
              exit 1
            fi

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
            nix flake update $INPUT

            ${rebuild} "update $INPUT"
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
            sanitize_label() {
              local input="$1"
              input="''${input// /_}"
              input="''${input//[^a-zA-Z0-9:_._-]/}"
              echo "$input"
            }

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

          ni = clap-bash.util.${pkgs.system}.writeClapScriptBin "ni" {
            name = "ni";
            about = "A small nix convenience wrapper";
            subcommand_required = true;
            subcommands = [
              {
                rebuild = {
                  about = "Rebuilds the NixOS environment";
                  executable = rebuild;
                  args = [
                    {
                      label = {
                        short = "l";
                        long = "label";
                      };
                    }
                    {
                      message = {
                        required = true;
                      };
                    }
                  ];
                };
              }
              {
                update = {
                  about = "Updates the system flake inputs and rebuilds";
                  executable = update;
                  args = [
                    {
                      input = {
                        takes_value = true;
                        multiple_values = true;
                      };
                    }
                  ];
                };
              }
              {
                sync = {
                  about = "Syncs system configuration with remote repository";
                  executable = sync;
                };
              }
              {
                test = {
                  about = "Tests the configuration without applying changes";
                  executable = test;
                };
              }
              {
                switch = {
                  about = "Switches to the new system generation";
                  executable = switch;
                  args = [
                    {
                      label = {
                        short = "l";
                        long = "label";
                      };
                    }
                    {
                      message = {
                        required = true;
                      };
                    }
                  ];
                };
              }
              {
                clean = {
                  about = "Cleans up old system generations and temporary files";
                  executable = clean;
                };
              }
            ];
          };
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
