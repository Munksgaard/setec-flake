{
  description = "Nix flake for Setec - Tailscale's secrets management service";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; };

  outputs = { self, nixpkgs }:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f:
        nixpkgs.lib.genAttrs supportedSystems (system:
          let
            overlay = final: prev: { setec = self.packages.${system}.setec; };
            pkgs = nixpkgs.legacyPackages.${system}.extend overlay;
          in f { pkgs = pkgs; });

    in {
      nixosModules = {
        default = import ./setec-module.nix;
        setec = import ./setec-module.nix;
      };

      packages = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.setec;
        setec = pkgs.buildGoModule (finalAttrs: rec {
          pname = "setec";
          version = "unstable-2024-09-27";

          src = pkgs.fetchFromGitHub {
            owner = "tailscale";
            repo = "setec";
            rev = "c57e4b5e91a275078b7fd4efd9bae30b93049812";
            hash = "sha256-xVXLjOHA25Rw+YMkljI0cMOK5aPVOnbcokGHcFUqEwk=";
          };

          vendorHash = "sha256-J0hcYnQIDwGx7wKwmZBqY/WmwQwpSF9Dj+9dzzvCDZ8=";

          meta = {
            description =
              "A secrets management service that uses Tailscale for access control";
            homepage =
              "https://tailscale.com/community/community-projects/setec";
            license = pkgs.lib.licenses.bsd3;
            maintainers = with pkgs.lib.maintainers; [ Munksgaard ];
          };
        });
      });

      checks = forEachSupportedSystem ({ pkgs }: {
        setecNixosTest = pkgs.nixosTest {
          name = "setec-boots";
          nodes.machine = { config, pkgs, ... }: {
            imports = [ self.nixosModules.setec ];
            services.setec = {
              enable = true;
              hostname = "setec-test";
              tsAuthkey = "tskey-auth-kWtZirNjtG11CNTRL-c8bhZWr4xoRr9pVeTVafoRciHkejBwm4";
            };

            system.stateVersion = "25.11";
          };

          testScript = ''
            machine.wait_for_unit("setec.service")

            def wait_for_systemctl_status_msg(_last_try):
              (_status, output) = machine.systemctl("status setec")
              return "AuthLoop: state is Running; done" in output

            retry(wait_for_systemctl_status_msg)
          '';
        };
      });
    };
}
