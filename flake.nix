{
  description = "A very basic flake";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; };

  outputs = inputs:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f:
        inputs.nixpkgs.lib.genAttrs supportedSystems
        (system: f { pkgs = import inputs.nixpkgs { inherit system; }; });
      setec = pkgs:
        pkgs.buildGoModule (finalAttrs: {
          pname = "setec";
          version = "0.0.0";

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
    in {
      packages = forEachSupportedSystem ({ pkgs }: {
        setec = setec pkgs;
        default = setec pkgs;
      });
    };
}
