{ config, lib, pkgs, ... }:
with lib;
let cfg = config.services.setec;
in {
  options.services.setec = {
    enable = mkEnableOption "a setec server";

    package = mkPackageOption pkgs "setec" { };

    tsAuthkey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Tailscale authentication key for connecting to the tailnet.
        WARNING: This will be stored in the Nix store and visible in process listings.
        Consider using tsAuthkeyFile instead for production.
      '';
      example = literalExpression
        "tskey-auth-kf4k3k3y4testCNTRL-ZmFrZSBrZXkgZm9yIHRlc3Q";
    };

    tsAuthkeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a file containing the Tailscale authentication key.
        This is more secure than tsAuthkey as it keeps the key out of the Nix store.
        The file should be readable by the setec user.
      '';
      example = literalExpression "/run/secrets/setec-tsauthkey";
    };

    hostname = mkOption {
      type = types.str;
      description = "Hostname for the setec server on the Tailscale network.";
      example = literalExpression "setec.example.ts.net";
    };

    stateDir = mkOption {
      type = types.path;
      description = "Directory where setec stores its state and database.";
      example = literalExpression "/var/lib/setec";
      default = "/var/lib/setec";
    };

    dev = mkOption {
      type = types.bool;
      description =
        "Whether to run setec in development mode (uses in-memory storage).";
      default = false;
    };

    kmsKeyName = mkOption {
      type = types.nullOr types.str;
      description = "AWS KMS key ARN for encrypting secrets.";
      default = null;
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
    assertions = [{
      assertion = (cfg.tsAuthkey != null) != (cfg.tsAuthkeyFile != null);
      message =
        "Exactly one of services.setec.tsAuthkey or services.setec.tsAuthkeyFile must be set.";
    }];

    users.users.setec = {
      description = "Setec secrets management service user";
      isSystemUser = true;
      group = "setec";
    };

    users.groups.setec = { };

    systemd.services.setec = {
      description = "Setec server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = [
        (builtins.dirOf
          config.security.wrapperDir) # for `su` to use taildrive with correct access rights
        pkgs.procps # for collecting running services (opt-in feature)
        pkgs.getent # for `getent` to look up user shells
        pkgs.kmod # required to pass tailscale's v6nat check
      ] ++ lib.optional config.networking.resolvconf.enable
        config.networking.resolvconf.package;

      requires = [ "network-online.target" ];

      environment = { TSNET_FORCE_LOGIN = "1"; };

      script = let
        authkeySetup = if cfg.tsAuthkeyFile != null then ''
          export TS_AUTHKEY="$(cat ${cfg.tsAuthkeyFile})"
        '' else ''
          export TS_AUTHKEY="${cfg.tsAuthkey}"
        '';
        kmsFlag = lib.optionalString (cfg.kmsKeyName != null)
          "--kms-key-name ${cfg.kmsKeyName}";
        backupBucketFlag = lib.optionalString (cfg.backupBucket != null)
          "--backup-bucket ${cfg.backupBucket}";
        backupRegionFlag = lib.optionalString (cfg.backupBucketRegion != null)
          "--backup-bucket-region ${cfg.backupBucketRegion}";
        backupRoleFlag = lib.optionalString (cfg.backupRole != null)
          "--backup-role ${cfg.backupRole}";
        devFlag = lib.optionalString cfg.dev "--dev";
      in ''
        ${authkeySetup}
        ${cfg.package}/bin/setec server --hostname "${cfg.hostname}" --state-dir "${cfg.stateDir}" ${kmsFlag} ${backupBucketFlag} ${backupRegionFlag} ${backupRoleFlag} ${devFlag}
      '';

      serviceConfig = {
        Type = "simple";
        User = "setec";
        Group = "setec";

        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies =
          [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";

        # State directory management
        # If using /var/lib, let systemd manage it; otherwise grant write access
        StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.stateDir)
          (lib.removePrefix "/var/lib/" cfg.stateDir);
        ReadWritePaths =
          lib.mkIf (!lib.hasPrefix "/var/lib/" cfg.stateDir) [ cfg.stateDir ];
      };
    };

  };
}
