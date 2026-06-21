{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "udp",
        "tag": "local",
        "server": "127.0.0.1",
        "server_port": 53
      }
    ],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": 5444,
      "users": [
        {
          "name": "sammy",
          "password": "azure://shelken-homelab/compose-vps/XRAY_VLESS_UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "git.opslab.net",
        "certificate_path": "/etc/sing-box/cert/cert.pem",
        "key_path": "/etc/sing-box/cert/key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_resolver": "local"
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "bittorrent",
        "action": "reject"
      }
    ],
    "final": "direct"
  }
}
