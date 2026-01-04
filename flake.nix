{
  description = "A small nix convenience wrapper";

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
          system = pkgs.stdenv.hostPlatform.system;

          run-as =
            user: env: user-script:
            let
              script = pkgs.writeShellScript "user-script" user-script;
              env-export = lib.concatStrings (builtins.map (var: ''export ${var}=\"''$${var}\";'') env);
            in
            ''
              su ${user} -s ${pkgs.bash}/bin/bash -c "${env-export}${script}"
            '';

          run-as-user = run-as "$SUDO_USER";

          ensure-root = ''
            set -e

            if [ "$(id -u)" -ne 0 ]; then
              exec sudo -E -H "$0" "$@"
            fi

            if [ -z "$SUDO_USER" ]; then
              echo "error: this script expects to be invoked via sudo by a non-root user" >&2
              exit 1
            fi
          '';

          parse-override-input =
            let
              script = pkgs.writeShellScript "script" ''
                parse_override_input() {
                    local input="$OVERRIDE_INPUT"
                    local override_args=""

                    IFS=',' read -ra items <<< "$input"
                    for item in "''${items[@]}"; do
                        IFS=';' read -ra subs <<< "$item"
                        if [ "''${#subs[@]}" -eq 2 ]; then
                            override_args+="--override-input ''${subs[0]} ''${subs[1]} "
                        fi
                    done

                    override_args="''${override_args%" "}"
                    echo "$override_args"
                }
                parse_override_input
              '';
            in
            "${script}";

          nixos-rebuild =
            operation: flags:
            pkgs.writeShellScript "nixos-wrapped-${operation}" ''
              ${ensure-root}
              set -eo pipefail

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

              cd $NIXOS_CONFIG

              ${run-as-user [ ] (
                pkgs.writeShellScript "git-add" ''
                  git add .
                ''
              )}

              ${
                let
                  base-command = ''NIXOS_LABEL="$NIXOS_LABEL" nixos-rebuild ${operation} ${lib.concatStringsSep " " flags} --flake $NIXOS_CONFIG#$NIXOS_HOST'';
                in
                if config.ni.nom.enable then
                  "${base-command} |& ${pkgs.nix-output-monitor}/bin/nom"
                else
                  base-command
              }
            '';

          rebuild = pkgs.writeShellScript "ni-rebuild" ''
            ${ensure-root}

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
            ${run-as-user [ ] (
              pkgs.writeShellScript "git-add" ''
                git add .
              ''
            )}

            # check if rebuild will work
            ${nixos-rebuild "dry-activate" [ ]}

            # sync git repo
            ${run-as-user [ "MESSAGE" ] (
              pkgs.writeShellScript "git-sync" ''
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
              ''
            )}

            ${switch}
          '';

          update = pkgs.writeShellScript "ni-update" ''
            ${ensure-root}

            NIXOS_CONFIG="${config.ni.nixos.config}"
            if [ -z "$NIXOS_CONFIG" ]; then
              echo "You must specify the path to the NixOS config!"
              exit 1
            fi
               
            cd $NIXOS_CONFIG
            if [ -z "$INPUT" ]; then
              nix flake update
            else
              IFS=',' read -ra parts <<< "$INPUT"
              for part in "''${parts[@]}"; do
                nix flake update "$part"
              done
            fi          

            MESSAGE="update $INPUT" ${rebuild}
          '';

          sync = pkgs.writeShellScript "ni-sync" ''
            ${ensure-root}

            NIXOS_CONFIG="${config.ni.nixos.config}"
            if [ -z "$NIXOS_CONFIG" ]; then
              echo "You must specify the path to the NixOS config!"
              exit 1
            fi

            cd $NIXOS_CONFIG
            hashes=$(${
              run-as-user [ ] (
                pkgs.writeShellScript "git-check-hash" ''
                  git add . >/dev/null
                  before=$(git rev-parse HEAD || true)
                  git pull --rebase >/dev/null || true
                  after=$(git rev-parse HEAD || true)
                  printf "%s %s" "$before" "$after"
                ''
              )
            })
            read old_hash new_hash <<< "$hashes"

            echo "old_hash: $old_hash"
            echo "new_hash: $new_hash"

            if [ "$old_hash" != "$new_hash" ]; then
              echo "Changes were pulled and applied."

              MESSAGE="sync" ${switch}
            else
              echo "No changes were pulled."
            fi
          '';

          test = pkgs.writeShellScript "ni-test" ''
            ${ensure-root}

            ${nixos-rebuild "test" [ ]}
          '';

          switch = pkgs.writeShellScript "ni-switch" ''
            ${ensure-root}

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
            ${ensure-root}

            nix-collect-garbage -d

            ${run-as-user [ ] (
              pkgs.writeShellScript "git-check-hash" ''
                nix-collect-garbage -d
              ''
            )}

            /run/current-system/bin/switch-to-configuration boot
          '';

          ni = clap-bash.util.${system}.writeClapScriptBin "ni" {
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
                        arg_action = "append";
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
                  args = [
                    {
                      override-input = {
                        long = "override-input";
                        env_var = "OVERRIDE_INPUT";
                        arg_action = "append";
                        number_of_values = 2;
                      };
                    }
                  ];
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
