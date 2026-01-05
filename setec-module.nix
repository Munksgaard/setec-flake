{ config, lib, pkgs, ... }:
with lib;
let cfg = config.services.setec;
in {
  options.services.setec = {
    enable = mkEnableOption "a setec server";

    package = mkPackageOption pkgs "setec" { };

    tsAuthkey = mkOption {
      type = types.str;
      example = literalExpression
        "tskey-auth-kf4k3k3y4testCNTRL-ZmFrZSBrZXkgZm9yIHRlc3Q";
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
      example = literalExpression
        "arn:aws:kms:us-east-1:123456789012:key/b8074b63-13c0-4345-a9d8-e236267d2af1";
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

    users.users.hello = {
      createHome = true;
      description = "helloNixosTests user";
      isSystemUser = true;
      group = "hello";
      home = "/srv/helloNixosTests";
    };

    users.groups.hello.gid = 1000;

    systemd.services.setec = {
      description = "Setec server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      # after = lib.mkIf (config.networking.networkmanager.enable) [ "NetworkManager-wait-online.service" ];

      path = [
        (builtins.dirOf
          config.security.wrapperDir) # for `su` to use taildrive with correct access rights
        pkgs.procps # for collecting running services (opt-in feature)
        pkgs.getent # for `getent` to look up user shells
        pkgs.kmod # required to pass tailscale's v6nat check
      ] ++ lib.optional config.networking.resolvconf.enable
        config.networking.resolvconf.package;

      requires = [ "network-online.target" ];

      environment = {
        TS_AUTHKEY = cfg.tsAuthkey;
        TSNET_FORCE_LOGIN = "1";
      };

      script = ''
        ${cfg.package}/bin/setec server --hostname "${cfg.hostname}" --state-dir "${cfg.stateDir}" ${lib.optionalString cfg.dev "--dev"}
      '';

      serviceConfig = {
        Type = "simple";

        User = "hello";
        Group = "hello";
        # DynamicUser = true;
        # WorkingDirectory = "/run/setec";
        # StateDirectory = "setec";
        # RuntimeDirectory = "setec";

        # PrivateTmp = true;
      };
    };

  };
}
