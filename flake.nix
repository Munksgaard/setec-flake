{
  description = "Nix flake for Setec - Tailscale's secrets management service";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        function: nixpkgs.lib.genAttrs supportedSystems (system: function nixpkgs.legacyPackages.${system});

      setecModule =
        {
          lib,
          pkgs,
          ...
        }:
        {
          imports = [ ./setec-module.nix ];
          services.setec.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.setec;
        };
    in
    {
      overlays.default = final: _previous: {
        setec = self.packages.${final.stdenv.hostPlatform.system}.setec;
      };

      nixosModules = {
        default = setecModule;
        setec = setecModule;
      };

      packages = forEachSupportedSystem (pkgs: rec {
        default = setec;
        setec = pkgs.buildGoModule {
          pname = "setec";
          version = "unstable-2026-08-08";

          src = pkgs.fetchFromGitHub {
            owner = "tailscale";
            repo = "setec";
            rev = "58bd74dcaa1a4e50589f5a3d0961cd30769246bd";
            hash = "sha256-8V8NwtZE+Ud5jW+4YO6hMruElaBQmvjG/tp+UTuVQx8=";
          };

          # The TPM simulator includes non-Go sources that `go mod vendor` omits.
          proxyVendor = true;
          vendorHash = "sha256-jGBxeIcFdplvgZh5GWx9Z1ciBSZQDlR4I/ryWBOnIBA=";

          # Upstream TPM simulator tests use cgo and link against OpenSSL.
          buildInputs = [ pkgs.openssl ];
          subPackages = [ "cmd/setec" ];

          meta = {
            description = "A secrets management service that uses Tailscale for access control";
            homepage = "https://github.com/tailscale/setec";
            license = pkgs.lib.licenses.bsd3;
            maintainers = with pkgs.lib.maintainers; [ Munksgaard ];
            mainProgram = "setec";
          };
        };
      });

      formatter = forEachSupportedSystem (pkgs: pkgs.nixfmt-tree);

      checks = forEachSupportedSystem (
        pkgs:
        nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          setecNixosTest = pkgs.testers.nixosTest {
            name = "setec-boots";
            nodes.machine = {
              imports = [ self.nixosModules.setec ];
              services.setec = {
                enable = true;
                hostname = "setec-test";
                tsAuthkeyFile = "/run/setec/missing-auth-key";
                dev = true;
              };

              system.stateVersion = "25.11";
            };

            testScript = ''
              machine.wait_for_unit("setec.service")
              machine.succeed("systemctl is-active setec.service")
              machine.wait_until_succeeds(
                  "journalctl -u setec.service | grep 'auth key file is missing, unreadable, or empty'"
              )
              machine.wait_until_succeeds(
                  "journalctl -u setec.service | grep 'LocalBackend state is NeedsLogin'"
              )
            '';
          };
        }
      );
    };
}
