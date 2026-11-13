{
  description = "Scriptorium Nim and ACP development environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      nimCompiler = pkgs.stdenv.mkDerivation {
        pname = "scriptorium-nim";
        version = "2.2.14";
        src = pkgs.fetchurl {
          url = "https://nim-lang.org/download/nim-2.2.14-linux_x64.tar.xz";
          hash = "sha256-wcvRBvn/DIVuOKvr0KyVA8I6ozkxdPz8MwfuOyv+kJo=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r bin lib config $out/
        '';
      };
    in pkgs.mkShell {
      packages = [ nimCompiler ] ++ (with pkgs; [ git gnumake pkg-config curlFull openssl.dev nodejs_24 ]);
      shellHook = ''
        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.curl pkgs.openssl ]}:$LD_LIBRARY_PATH
        export LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.openssl ]}:$LIBRARY_PATH
        export PATH="$PWD/.build/agent-tools/node_modules/.bin:$PATH"
      '';
    };
  };
}
