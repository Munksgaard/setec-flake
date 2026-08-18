{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.setec;
  inherit (lib)
    escapeShellArg
    getExe
    hasPrefix
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalString
    removePrefix
    types
    ;
in
{
  options.services.setec = {
    enable = mkEnableOption "a setec server";

    package = mkOption {
      type = types.package;
      description = "The setec package to run.";
    };

    tsAuthkey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Tailscale authentication key used for initial tailnet enrollment.
        WARNING: This value is stored in the Nix store. Use tsAuthkeyFile for production.
        The key is optional after tsnet state has been enrolled and persisted.
      '';
      example = "tskey-auth-kf4k3k3y4testCNTRL-ZmFrZSBrZXkgZm9yIHRlc3Q";
    };

    tsAuthkeyFile = mkOption {
      type = types.nullOr types.externalPath;
      default = null;
      description = ''
        Runtime path to a file containing the Tailscale authentication key used for
        initial enrollment. When the file is absent, setec starts without TS_AUTHKEY
        and reuses its persisted tsnet state.
      '';
      example = "/run/secrets/setec-tsauthkey";
    };

    hostname = mkOption {
      type = types.str;
      description = "Short hostname for the setec server's tsnet node.";
      example = "secrets";
    };

    stateDir = mkOption {
      type = types.externalPath;
      description = "Directory where setec stores its state and database.";
      example = "/var/lib/setec";
      default = "/var/lib/setec";
    };

    dev = mkOption {
      type = types.bool;
      description = "Whether to use setec's insecure static development encryption key.";
      default = false;
    };

    kmsKeyName = mkOption {
      type = types.nullOr types.str;
      description = "AWS KMS key ARN used to encrypt the setec database.";
      default = null;
      example = "arn:aws:kms:us-east-1:123456789012:key/b8074b63-13c0-4345-a9d8-e236267d2af1";
    };

    kmsKeyNameFile = mkOption {
      type = types.nullOr types.externalPath;
      default = null;
      description = "Runtime path to a file containing the AWS KMS key ARN.";
      example = "/run/config/setec-kms-key";
    };

    backupBucket = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of the AWS S3 bucket used for database backups.";
    };

    backupBucketRegion = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "AWS region of the database backup bucket.";
    };

    backupRole = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "AWS IAM role ARN to assume when writing database backups.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.tsAuthkey != null && cfg.tsAuthkeyFile != null);
        message = "Only one of services.setec.tsAuthkey or services.setec.tsAuthkeyFile can be set.";
      }
      {
        assertion = !(cfg.kmsKeyName != null && cfg.kmsKeyNameFile != null);
        message = "Only one of services.setec.kmsKeyName or services.setec.kmsKeyNameFile can be set.";
      }
      {
        assertion = cfg.dev || cfg.kmsKeyName != null || cfg.kmsKeyNameFile != null;
        message = "services.setec requires kmsKeyName or kmsKeyNameFile unless dev mode is enabled.";
      }
    ];

    users.users.setec = {
      description = "Setec secrets management service user";
      isSystemUser = true;
      group = "setec";
    };

    users.groups.setec = { };

    systemd.services.setec = {
      description = "Setec server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;

      path = [
        # Dependencies used by tailscale's hostinfo and networking checks.
        (builtins.dirOf config.security.wrapperDir)
        pkgs.procps
        pkgs.getent
        pkgs.kmod
      ]
      ++ optional config.networking.resolvconf.enable config.networking.resolvconf.package;

      script =
        let
          authkeySetup =
            if cfg.tsAuthkeyFile != null then
              ''
                if [[ -r ${escapeShellArg cfg.tsAuthkeyFile} && -s ${escapeShellArg cfg.tsAuthkeyFile} ]]; then
                  export TS_AUTHKEY="$(< ${escapeShellArg cfg.tsAuthkeyFile})"
                else
                  echo ${escapeShellArg "setec: auth key file is missing, unreadable, or empty; relying on persisted tsnet state: ${cfg.tsAuthkeyFile}"} >&2
                fi
              ''
            else
              optionalString (cfg.tsAuthkey != null) ''
                export TS_AUTHKEY=${escapeShellArg cfg.tsAuthkey}
              '';
          kmsKeySetup =
            if cfg.kmsKeyNameFile != null then
              ''
                if [[ ! -r ${escapeShellArg cfg.kmsKeyNameFile} || ! -s ${escapeShellArg cfg.kmsKeyNameFile} ]]; then
                  echo ${escapeShellArg "setec: KMS key file is missing, unreadable, or empty: ${cfg.kmsKeyNameFile}"} >&2
                  exit 1
                fi
                args+=(--kms-key-name "$(< ${escapeShellArg cfg.kmsKeyNameFile})")
              ''
            else
              optionalString (cfg.kmsKeyName != null) ''
                args+=(--kms-key-name ${escapeShellArg cfg.kmsKeyName})
              '';
        in
        ''
          ${authkeySetup}

          args=(
            server
            --hostname ${escapeShellArg cfg.hostname}
            --state-dir ${escapeShellArg cfg.stateDir}
          )
          ${kmsKeySetup}
          ${optionalString (
            cfg.backupBucket != null
          ) "args+=(--backup-bucket ${escapeShellArg cfg.backupBucket})"}
          ${optionalString (
            cfg.backupBucketRegion != null
          ) "args+=(--backup-bucket-region ${escapeShellArg cfg.backupBucketRegion})"}
          ${optionalString (cfg.backupRole != null) "args+=(--backup-role ${escapeShellArg cfg.backupRole})"}
          ${optionalString cfg.dev "args+=(--dev)"}

          exec ${getExe cfg.package} "''${args[@]}"
        '';

      serviceConfig = {
        Type = "simple";
        User = "setec";
        Group = "setec";
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";

        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";

        # If using /var/lib, let systemd manage it; otherwise grant write access.
        StateDirectory = mkIf (hasPrefix "/var/lib/" cfg.stateDir) (removePrefix "/var/lib/" cfg.stateDir);
        ReadWritePaths = mkIf (!hasPrefix "/var/lib/" cfg.stateDir) [ cfg.stateDir ];
      };
    };
  };
}
