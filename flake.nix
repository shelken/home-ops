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
        name = "base template";

        packages = with pkgs; [
          fluxcd
          k9s

          kustomize

          ansible
          k3sup

          opentofu
        ];

        shellHook = ''
          echo "环境初始化成功"
          export KUBECONFIG=`pwd`/kubeconfig
          export ANSIBLE_CONFIG=`pwd`/ansible/ansible.cfg
        '';

        # Now we can execute any commands within the virtual environment.
        # This is optional and can be left out to run pip manually.
        postShellHook = ''
          # allow pip to install wheels
        '';
      };
    });
}
