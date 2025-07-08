{
  description = "Base development template";

  inputs = {
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    utils,
    ...
  }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShells.default = pkgs.mkShell {
        name = "home-ops";

        packages = with pkgs; [
          # fluxcd
          k9s

          kustomize

          ansible
          k3sup

          opentofu

          kubernetes-helm
          cilium-cli

          sops
          go-task

          helmfile
          # talosctl
        ];

        shellHook = ''
          unset GITHUB_TOKEN
          alias flux=/opt/brew/bin/flux
          export KUBECONFIG=`pwd`/kubeconfig
          export ANSIBLE_CONFIG=`pwd`/ansible/ansible.cfg
          export SOPS_AGE_KEY_FILE=~/.config/sops/age/home-ops.txt

          echo "环境初始化成功"
        '';

        # Now we can execute any commands within the virtual environment.
        # This is optional and can be left out to run pip manually.
        postShellHook = ''
          # allow pip to install wheels
        '';
      };
    });
}
