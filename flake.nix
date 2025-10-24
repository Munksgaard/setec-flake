{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          let
            overlay = final: prev: { setec = self.packages.${system}.setec; };

            pkgs_old = import nixpkgs { inherit system; };

            pkgs = nixpkgs.legacyPackages.${system}.extend overlay;

          in
          f { pkgs = pkgs; }
        );

    in
    {
      nixosModules = {
        setec = import ./setec-module.nix;
      };

      packages = forEachSupportedSystem (
        { pkgs }:
        {
          setec = pkgs.callPackage ./setec-package.nix { };
        }
      );

      checks = forEachSupportedSystem (
        { pkgs }:
        {
          setecNixosTest = pkgs.nixosTest {
            name = "setec-boots";
            nodes = {
              server =
                { config, pkgs, ... }:
                {
                  imports = [ self.nixosModules.setec ];

                  environment.systemPackages = [ pkgs.setec ];

                  networking.firewall.allowedTCPPorts = [ 443 ];

                  services.setec = {
                    enable = true;
                    hostname = "setec-test";
                    dev = true;
                  };

                  systemd.tmpfiles.rules = [
                    "f+ /var/lib/setec/settings.env 0444 root root - TS_AUTHKEY=tskey-auth-kWtZirNjtG11CNTRL-c8bhZWr4xoRr9pVeTVafoRciHkejBwm4"
                  ];

                  system.stateVersion = "25.11";
                };
              client =
                { pkgs, ... }:
                {
                  environment.systemPackages = [ pkgs.setec ];

                  system.stateVersion = "25.11";
                };
            };

            testScript = ''
              start_all()

              server.wait_for_unit("setec.service")

              # server.succeed('echo -n "hello, world" | setec -s https://server put dev/hello-world')

              # def wait_for_systemctl_status_msg(_last_try):
              #   (_status, output) = machine.systemctl("status setec")
              #   return "AuthLoop: state is Running; done" in output

              client.succeed('echo -n "hello, world" | setec -s https://server put dev/hello-world')

              # retry(wait_for_systemctl_status_msg)
            '';
          };
        }
      );
    };
}
