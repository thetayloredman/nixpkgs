{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.gomuks-web;
  dataDir = "/var/lib/gomuks-web";

  settingsFile = instance: "${dataDir}/${instance}/config/config.yaml";
  settingsFormat = pkgs.formats.yaml { };
  settingsFileUnsubstituted =
    instance:
    settingsFormat.generate "gomuks-web-config-${instance}-unsubstituted.yaml" (
      cfg.instances.${instance}.settings or { }
    );

  defaultConfig = { };
in
{
  options.services.gomuks-web = {
    enable = lib.mkEnableOption "gomuks-web, a Matrix client written in Go";

    package = lib.mkPackageOption pkgs "gomuks-web" { };

    instances = lib.mkOption {
      description = "List of gomuks-web instances to run";
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            settings = lib.mkOption {
              apply = lib.recursiveUpdate defaultConfig;
              description = ''
                {file}`config.yaml` configuration as a Nix attribute set.
                Secrets should be specified using {option}`environmentFile` instead of this world-readable attribute set.
              '';
              type = settingsFormat.type;
              default = defaultConfig;
              example = {
                web = {
                  username = "user";
                  password_hash = "$GOMUKS_WEB_PASSWORD_HASH";
                };
              };
            };

            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                File containing environment variables to pass to gomuks-web, and be substituted into {option}`settings`.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.gomuks-web = {
      isSystemUser = true;
      group = "gomuks-web";
      home = dataDir;
      description = "gomuks-web user";
    };

    users.groups.gomuks-web = { };

    systemd.services = lib.mapAttrs' (
      name: instanceCfg:
      lib.nameValuePair "gomuks-web-${name}" {
        description = "gomuks-web ${name}";

        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        preStart = ''
          # substitute environment variables into the settings file
          test -f '${settingsFile name}' && rm -f '${settingsFile name}'
          old_umask=$(umask)
          umask 0177
          ${pkgs.envsubst}/bin/envsubst \
            -o '${settingsFile name}' \
            -i '${settingsFileUnsubstituted name}'
          umask $old_umask
        '';

        serviceConfig = {
          User = "gomuks-web";
          Group = "gomuks-web";
          EnvironmentFile = lib.mkIf (instanceCfg.environmentFile != null) (
            toString instanceCfg.environmentFile
          );
          Environment = "GOMUKS_ROOT=${dataDir}/${name}";
          ExecStart = "${cfg.package}/bin/gomuks-web";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          LockPersonality = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
        };
      }
    );
  };

  meta.maintainers = with lib.maintainers; [ logn ];
}
