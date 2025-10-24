{
  config,
  lib,
  pkgs,
  ...
}:

# in order to use this, create a file out-of-band at /var/lib/setec/settings.env that contains the variables required
# for authenticating against AWS KMS and Tailscale.
#
# Example:
# 
# AWS_ACCESS_KEY_ID=AKIATI.....
# AWS_SECRET_ACCESS_KEY=18UuL12k.....
# TS_AUTHKEY=tskey-auth-kB1o.....

let
  cfg = config.services.setec;

  inherit (lib)
    mkEnableOption
    mkPackageOption
    mkOption
    literalExpression
    types
    mkIf
    ;

  homeDir = "/var/lib/setec";

in
{
  options.services.setec = {
    enable = mkEnableOption "a setec server";

    package = mkPackageOption pkgs "setec" { };

    openFirewall = lib.mkOption {
      description = "Open firewall";
      type = lib.types.bool;
      default = true;
    };

    hostname = mkOption {
      type = types.str;
      example = literalExpression "setec.example.ts.net";
    };

    stateDir = mkOption {
      type = types.path;
      example = literalExpression "/run/setec";
      default = "/run/setec/tmp";
    };

    dev = mkOption {
      type = types.bool;
      default = false;
    };

    kmsKeyName = mkOption {
      type = types.nullOr types.str;
      example = literalExpression "arn:aws:kms:us-east-1:123456789012:key/b8074b63-13c0-4345-a9d8-e236267d2af1";
    };

    backupBucket = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of AWS S3 bucket to use for database backups.";
    };

    backupBucketRegion = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "AWS region of the backup S3 bucket.";
    };

    backupRole = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of AWS IAM role to assume to write backups.";
    };

  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 443 ];

    users.users.setec = {
      createHome = true;
      description = "setec";
      isSystemUser = true;
      group = "setec";
      home = homeDir;
    };

    users.groups.setec = { };

    systemd.services.setec = {
      description = "Setec server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = map lib.getBin (
        [
          (builtins.dirOf config.security.wrapperDir) # for `su` to use taildrive with correct access rights
          pkgs.procps # for collecting running services (opt-in feature)
          pkgs.getent # for `getent` to look up user shells
          pkgs.kmod # required to pass tailscale's v6nat check
        ]
        ++ lib.optionals config.networking.resolvconf.enable [ config.networking.resolvconf.package ]
      );

      requires = [ "network-online.target" ];

      environment = {
        TSNET_FORCE_LOGIN = "1";
      };

      serviceConfig = {
        Type = "exec";
        User = "setec";
        Group = "setec";
        ExecStart = lib.concatStringsSep " " (
          [
            (lib.getExe cfg.package)
            "server"
            "--hostname"
            cfg.hostname
            "--state-dir"
            homeDir
          ]
          ++ (if cfg.dev then [ "--dev" ] else [ "--kms-key-name=${cfg.kmsKeyName}" ])
        );
        EnvironmentFile = [ "${homeDir}/settings.env" ];
        PrivateTmp = true;
      };
    };
  };
}
