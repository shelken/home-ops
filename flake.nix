{
  description = "Base development template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils = {
      url = "github:numtide/flake-utils";
    };
  };

  outputs =
    {
      nixpkgs,
      utils,
      ...
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
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

            helmfile
            # talosctl

            gitleaks

            # Linting
            yamllint

            # Home Assistant CLI
            home-assistant-cli
          ];

          shellHook = ''
            export KUBECONFIG=`pwd`/kubeconfig
            export ANSIBLE_CONFIG=`pwd`/ansible/ansible.cfg
            export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

            # crowdsec cli. before we run it, run `APP_NAME="crowdsec-lapi" && POD_NAME=$(k get pod -l "app.kubernetes.io/name=$APP_NAME" -A -o jsonpath='{.items[0].metadata.name}') && POD_NAMESPACE=$(k get pod -l "app.kubernetes.io/name=$APP_NAME" -A -o jsonpath='{.items[0].metadata.namespace}')`
            alias cscli="k exec -it \$POD_NAME -n \$POD_NAMESPACE -- cscli"

            echo "环境初始化成功"
          '';

          # Now we can execute any commands within the virtual environment.
          # This is optional and can be left out to run pip manually.
          postShellHook = ''

          '';
        };
      }
    );
}
