{
  description = "A Nix-flake-based development environment for Chipwhisperer";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, ... }@inputs:

    let
      inherit (inputs.nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs { inherit system; };
          }
        );

      # DO NOT CHANGE
      # Chipwhisperer requires numpy v1 which is only available in python 3.12
      version = "3.12";
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, ... }:
        let
          concatMajorMinor =
            v:
            lib.pipe v [
              lib.versions.splitVersion
              (lib.sublist 0 2)
              lib.concatStrings
            ];

          # Build the Python 3.12 set against numpy v1 (numpy_1) and fix up the
          # upstream-broken chipwhisperer package
          python = pkgs."python${concatMajorMinor version}".override {
            self = python;

            packageOverrides = pyfinal: pyprev: {
              # Switch to numpy v1
              numpy = pyprev.numpy_1;

              chipwhisperer = pyprev.chipwhisperer.overridePythonAttrs (old: {
                # Add numpy v1 here
                dependencies = (old.dependencies or [ ]) ++ [ pyfinal.numpy ];

                # And remove the relaxation requirement for it
                pythonRelaxDeps = [];

                # Remove broken flag to get it to build
                meta = old.meta // { broken = false; };
              });
            };
          };
        in
        {
          default = pkgs.mkShellNoCC {
            venvDir = ".venv";

            postShellHook = ''
              venvVersionWarn() {
              	local venvVersion
              	venvVersion="$("$venvDir/bin/python" -c 'import platform; print(platform.python_version())')"

              	[[ "$venvVersion" == "${python.version}" ]] && return

              	cat <<EOF
              Warning: Python version mismatch: [$venvVersion (venv)] != [${python.version}]
                       Delete '$venvDir' and reload to rebuild for version ${python.version}
              EOF
              }

              venvVersionWarn
            '';

            packages =
              (with python.pkgs; [
                venvShellHook
                pip

                chipwhisperer
              ]);
          };
        }
      );
    };
}
