{
  fetchFromGitHub,
  lib,
  buildGoModule,
}:

buildGoModule (finalAttrs: {
  pname = "setec";
  version = "0-unstable-2025-10-19";

  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "setec";
    rev = "c57e4b5e91a275078b7fd4efd9bae30b93049812";
    hash = "sha256-xVXLjOHA25Rw+YMkljI0cMOK5aPVOnbcokGHcFUqEwk=";
  };

  vendorHash = "sha256-J0hcYnQIDwGx7wKwmZBqY/WmwQwpSF9Dj+9dzzvCDZ8=";

  meta = {
    description = "A secrets management service that uses Tailscale for access control";
    homepage = "https://tailscale.com/community/community-projects/setec";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ Munksgaard ];
    mainProgram = "setec";
  };
})
