## 密钥管理


### sops

```shell
nix shell nixpkgs#sops nixpkgs#go-task

task encrypt-all # 一次性加密所有需要未加密文件

task updatekey-all # 变更/删除/增加密钥时 一次性更新所有已加密的文件

task deploy-secret # 将sops-age部署到flux-system
```
