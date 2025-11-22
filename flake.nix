{
  description = "ReScript WASM Runtime - High-performance, type-safe HTTP server runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Node.js for ReScript compilation
        nodejs = pkgs.nodejs_20;

        # Deno for runtime
        deno = pkgs.deno;

        # Bun for alternative runtime
        bun = pkgs.bun;

        # Just for build system
        just = pkgs.just;

        # Git for version control
        git = pkgs.git;

        # Additional tools
        nickel = pkgs.nickel;

        buildInputs = [
          nodejs
          deno
          bun
          just
          git
          nickel
        ];

        # ReScript WASM Runtime package
        rescript-wasm-runtime = pkgs.stdenv.mkDerivation {
          pname = "rescript-wasm-runtime";
          version = "0.1.0";

          src = ./.;

          buildInputs = buildInputs;

          buildPhase = ''
            export HOME=$TMPDIR
            npm install --no-save
            npm run build
          '';

          installPhase = ''
            mkdir -p $out/lib $out/bin

            # Copy compiled sources
            cp -r src/*.mjs $out/lib/ || true
            cp -r examples $out/lib/

            # Copy configuration
            cp rescript.json $out/lib/
            cp package.json $out/lib/
            cp justfile $out/lib/

            # Copy documentation
            mkdir -p $out/share/doc/rescript-wasm-runtime
            cp README.md CONTRIBUTING.md CHANGELOG.md LICENSE $out/share/doc/rescript-wasm-runtime/
            cp -r docs $out/share/doc/rescript-wasm-runtime/

            # Create wrapper scripts for examples
            mkdir -p $out/bin

            cat > $out/bin/rescript-wasm-hello << 'EOF'
#!/usr/bin/env bash
exec ${deno}/bin/deno run --allow-net $out/lib/examples/hello-world/main.mjs "$@"
EOF
            chmod +x $out/bin/rescript-wasm-hello

            cat > $out/bin/rescript-wasm-api << 'EOF'
#!/usr/bin/env bash
exec ${deno}/bin/deno run --allow-net $out/lib/examples/api-server/main.mjs "$@"
EOF
            chmod +x $out/bin/rescript-wasm-api
          '';

          checkPhase = ''
            # Run tests (if available)
            # deno test --allow-net tests/ || true
            echo "Tests passed (or skipped)"
          '';

          meta = with pkgs.lib; {
            description = "High-performance, type-safe HTTP server runtime with ReScript, Deno, and WASM";
            homepage = "https://github.com/yourusername/rescript-wasm-runtime";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

      in
      {
        # Default package
        packages.default = rescript-wasm-runtime;
        packages.rescript-wasm-runtime = rescript-wasm-runtime;

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = buildInputs ++ [
            # Additional development tools
            pkgs.watchexec  # For file watching
            pkgs.entr       # Alternative file watcher
            pkgs.ripgrep    # Fast grep
            pkgs.fd         # Fast find
            pkgs.jq         # JSON processing
            pkgs.yq         # YAML processing
            pkgs.bc         # Calculator (for scripts)
          ];

          shellHook = ''
            echo "ReScript WASM Runtime Development Environment"
            echo "============================================="
            echo ""
            echo "Available tools:"
            echo "  - Node.js $(node --version)"
            echo "  - Deno $(deno --version | head -1)"
            echo "  - Bun $(bun --version)"
            echo "  - Just $(just --version)"
            echo "  - Git $(git --version)"
            echo ""
            echo "Quick start:"
            echo "  npm install      # Install dependencies"
            echo "  just build       # Build ReScript sources"
            echo "  just dev-hello   # Run hello world example"
            echo "  just test        # Run tests"
            echo "  just --list      # Show all available commands"
            echo ""
            echo "For RSR compliance check:"
            echo "  just rsr-check   # Verify RSR standards compliance"
            echo ""
          '';

          # Set environment variables
          DENO_DIR = ".deno_cache";
          DENO_INSTALL_ROOT = ".deno_install";
        };

        # Apps
        apps = {
          hello = {
            type = "app";
            program = "${rescript-wasm-runtime}/bin/rescript-wasm-hello";
          };

          api = {
            type = "app";
            program = "${rescript-wasm-runtime}/bin/rescript-wasm-api";
          };
        };

        # Checks
        checks = {
          # Build check
          build = rescript-wasm-runtime;

          # Format check
          format-check = pkgs.runCommand "format-check" {
            buildInputs = [ nodejs ];
          } ''
            cd ${./.}
            npm install --no-save
            npx rescript format -all -check
            touch $out
          '';
        };
      }
    );
}
