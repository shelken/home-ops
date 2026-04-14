{
  description = "Base development template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils = {
      url = "github:numtide/flake-utils";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      utils,
      git-hooks,
      ...
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        pre-commit-check = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            end-of-file-fixer = {
              enable = true;
            };

            trim-trailing-whitespace = {
              enable = true;
            };

            check-merge-conflicts = {
              enable = true;
            };

            yamllint = {
              enable = true;
              settings.strict = false;
              settings.configuration = ''
                extends: relaxed
                rules:
                  line-length: disable
              '';
            };

            gitleaks = {
              enable = true;
              name = "gitleaks";
              entry = "gitleaks protect --staged --config gitleaks.toml --redact -v";
              pass_filenames = false;
              language = "system";
            };
          };
        };
      in
      {
        checks.pre-commit-check = pre-commit-check;
        devShells.default = pkgs.mkShell {
          name = "home-ops";

          packages = with pkgs; [
            # azure-cli

            # k9s
            kustomize
            krew

            ansible
            fluxcd
            # k3sup

            # opentofu

            kubernetes-helm
            cilium-cli

            sops
            go-task
            gum

            helmfile
            # talosctl

            gitleaks

            # Linting
            yamllint

            # Home Assistant CLI
            home-assistant-cli
          ];

          shellHook = ''
            ${pre-commit-check.shellHook}
            export KUBECONFIG=`pwd`/kubeconfig
            export ANSIBLE_CONFIG=`pwd`/ansible/ansible.cfg
            export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

            # crowdsec cli. before we run it, run `APP_NAME="crowdsec-lapi" && POD_NAME=$(k get pod -l "app.kubernetes.io/name=$APP_NAME" -A -o jsonpath='{.items[0].metadata.name}') && POD_NAMESPACE=$(k get pod -l "app.kubernetes.io/name=$APP_NAME" -A -o jsonpath='{.items[0].metadata.namespace}')`
            alias cscli="k exec -it \$POD_NAME -n \$POD_NAMESPACE -- cscli"

            echo "环境初始化成功"
          '';

          postShellHook = ''

          '';
        };
      }
    );
}
