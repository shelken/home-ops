# Spec: DDNS Routing

## ADDED Requirements

### Requirement: ISP-Aware IPv6 Selection

DDNS 更新服务 SHALL 根据当前检测到的 IPv6 地址前缀选择正确的 DNS 记录值：

- 当检测到的 IPv6 地址以 `2408:` 开头时，SHALL 使用自动检测的 IPv6 地址
- 当检测到的 IPv6 地址不以 `2408:` 开头时，SHALL 使用预定义的 VPS IPv6 地址（`MAIN_VPS_IP_V6`）

#### Scenario: 联通网络环境（2408 前缀）
- **GIVEN** 当前网络环境的 IPv6 地址以 `2408:` 开头
- **WHEN** DDNS 服务查询当前应使用的 IP 地址
- **THEN** 返回自动检测的 IPv6 地址

#### Scenario: 移动网络环境（非 2408 前缀）
- **GIVEN** 当前网络环境的 IPv6 地址不以 `2408:` 开头
- **WHEN** DDNS 服务查询当前应使用的 IP 地址
- **THEN** 返回预定义的 VPS IPv6 地址

#### Scenario: IPv6 检测失败
- **GIVEN** 无法检测到当前网络的 IPv6 地址
- **WHEN** DDNS 服务查询当前应使用的 IP 地址
- **THEN** 返回预定义的 VPS IPv6 地址作为回退
