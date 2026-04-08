{
  description = "Nim development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    {
      devShells.x86_64-linux.default = 
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          buildInputs = with pkgs; [
            nim
            nimble
            curlFull
          ];
          
          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.curl.out}/lib:$LD_LIBRARY_PATH

            # Build typoi from nimby-installed Typos package and add to PATH
            TYPOS_SRC="$HOME/.nimby/pkgs/Typos"
            TYPOI_BIN="$PWD/.bin/typoi"
            if [ -d "$TYPOS_SRC" ]; then
              mkdir -p "$PWD/.bin"
              if [ ! -f "$TYPOI_BIN" ] || [ "$TYPOS_SRC/src/typoi.nim" -nt "$TYPOI_BIN" ]; then
                echo "Building typoi from $TYPOS_SRC..."
                nim c -d:release -o:"$TYPOI_BIN" "$TYPOS_SRC/src/typoi.nim" 2>&1
              fi
              export PATH="$PWD/.bin:$PATH"
            fi
          '';
        };
    };
} 
