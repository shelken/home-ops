{
  description = "Base development template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.05";
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
            # kustomize
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

          ];

          shellHook = ''
            export KUBECONFIG=`pwd`/kubeconfig
            export ANSIBLE_CONFIG=`pwd`/ansible/ansible.cfg
            export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

            echo "环境初始化成功"
          '';

          # Now we can execute any commands within the virtual environment.
          # This is optional and can be left out to run pip manually.
          postShellHook = ''
            # allow pip to install wheels
          '';
        };
      }
    );
}
