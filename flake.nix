{
  description = "Scriptorium Nim and ACP development environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in pkgs.mkShell {
      packages = with pkgs; [ nim git gnumake pkg-config curlFull openssl.dev nodejs_24 ];
      shellHook = ''
        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.curl pkgs.openssl ]}:$LD_LIBRARY_PATH
        export LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.openssl ]}:$LIBRARY_PATH
        export PATH="$PWD/.build/nim-2.2.14/bin:$PWD/.build/agent-tools/node_modules/.bin:$PATH"
      '';
    };
  };
}
