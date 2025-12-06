{
  description = "GitHub Action for caching Nix derivations with S3";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              shellcheck
              shfmt
              yamllint
              markdownlint-cli2
              actionlint
            ];
          };
        });

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          shellcheck = pkgs.runCommand "shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
            cd ${self}
            shellcheck $(find . -name '*.sh' -type f)
            touch $out
          '';

          shfmt = pkgs.runCommand "shfmt" { nativeBuildInputs = [ pkgs.shfmt ]; } ''
            cd ${self}
            shfmt -d -i 2 -ci $(find . -name '*.sh' -type f)
            touch $out
          '';

          yamllint = pkgs.runCommand "yamllint" { nativeBuildInputs = [ pkgs.yamllint ]; } ''
            cd ${self}
            yamllint -d relaxed .
            touch $out
          '';

          markdownlint = pkgs.runCommand "markdownlint" { nativeBuildInputs = [ pkgs.markdownlint-cli2 ]; } ''
            cd ${self}
            markdownlint-cli2 "**/*.md"
            touch $out
          '';

          actionlint = pkgs.runCommand "actionlint" { nativeBuildInputs = [ pkgs.actionlint ]; } ''
            actionlint ${self}/.github/workflows/*.yml
            touch $out
          '';
        });
    };
}
