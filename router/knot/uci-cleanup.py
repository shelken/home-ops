#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys


def run(args, text=None):
    return subprocess.run(args, input=text, stdin=subprocess.DEVNULL if text is None else None,
                          text=True, capture_output=True, check=True).stdout


def parse_uci(text):
    sections = {}
    for line in text.splitlines():
        match = re.fullmatch(r"dhcp\.([\w]+)(?:\.([\w]+))?=(.*)", line)
        if not match:
            continue
        section, key, value = match.groups()
        value = shlex.split(value)
        sections.setdefault(section, {})[key or 'kind'] = ' '.join(value)
    return {section: (item['kind'], item.get('name' if item['kind'] == 'domain' else 'cname', ''),
                      item.get('ip' if item['kind'] == 'domain' else 'target', ''))
            for section, item in sections.items() if item.get('kind') in ('domain', 'cname')}


def in_zone(name, zone):
    return name == zone or name.endswith('.' + zone)


def records(text, names, main, internal, second):
    result = {}
    for section, (kind, name, target) in parse_uci(text).items():
        name = name.lower().rstrip('.')
        if in_zone(name, second) or not (in_zone(name, main) or in_zone(name, internal)):
            continue
        result[section] = (kind, name, target, '集群同名' if name in names else '手工/孤儿')
    return result


def main():
    if sys.argv[1:] == ['--self-test']:
        fixture = "dhcp.cfg1=domain\ndhcp.cfg1.name='live.int.example.test'\ndhcp.cfg1.ip='192.0.2.1'\ndhcp.cfg2=cname\ndhcp.cfg2.cname='manual.example.test'\ndhcp.cfg2.target='outside.example.net'\ndhcp.cfg3=domain\ndhcp.cfg3.name='echo.second.test'\ndhcp.cfg3.ip='192.0.2.2'\ndhcp.cfg4=domain\ndhcp.cfg4.name='notexample.test'\ndhcp.cfg4.ip='192.0.2.3'\n"
        assert records(fixture, {'live.int.example.test'}, 'example.test', 'int.example.test', 'second.test') == {
            'cfg1': ('domain', 'live.int.example.test', '192.0.2.1', '集群同名'),
            'cfg2': ('cname', 'manual.example.test', 'outside.example.net', '手工/孤儿')}
        print('通过：A/CNAME、手工保留、第二域与相似后缀排除')
        return
    action, *selected = sys.argv[1:]
    if action not in ('list', 'delete') or (action == 'delete' and not selected):
        raise ValueError('用法：uci-cleanup.py list | delete <UCI 段名...>')
    ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', os.environ['ROUTER_SSH']]
    resources = json.loads(run(['kubectl', 'get', 'httproute,ingress,service', '-A', '-o', 'json']))
    names = set()
    for resource in resources['items']:
        spec = resource.get('spec', {})
        names.update(spec.get('hostnames', []))
        names.update(rule['host'] for rule in spec.get('rules', []) if rule.get('host'))
        annotations = resource.get('metadata', {}).get('annotations', {})
        for prefix in ('external-dns.alpha.kubernetes.io/', 'internal.external-dns.alpha.kubernetes.io/'):
            names.update(n.strip() for n in annotations.get(prefix + 'hostname', '').split(',') if n.strip())
    names = {n.lower().rstrip('.') for n in names}
    snapshot = run(ssh + ['uci -X show dhcp'])
    table = records(snapshot, names, os.environ['MAIN_DOMAIN'], os.environ['INTERNAL_DOMAIN'], os.environ['SECOND_DOMAIN'])
    if action == 'list':
        for section, (kind, name, target, category) in table.items():
            print(f'{section}\t{kind}\t{name}\t{target}\t{category}')
        print('集群同名不证明记录由 webhook 创建；手工/孤儿需逐个核对消费者。')
        return
    deployment = json.loads(run(['kubectl', '-n', 'network', 'get', 'deployment', 'external-dns-openwrt', '-o', 'json']))
    args = deployment['spec']['template']['spec']['containers'][0]['args']
    if '--provider=rfc2136' not in args:
        raise ValueError('旧 webhook 尚未停止写入，禁止清理')
    if len(set(selected)) != len(selected) or any(section not in table for section in selected):
        raise ValueError('只接受 list 展示的唯一 UCI 段名')
    for section in selected:
        kind, name, target, category = table[section]
        print(f'{section}: {name} -> {target} [{category}]')
        if category == '手工/孤儿' and input(f'已确认 {name} 无消费者依赖此覆盖？输入完整名称确认：') != name:
            raise ValueError('未确认消费者，取消')
    if input('仅删除上述条目，输入 DELETE 确认：') != 'DELETE':
        raise ValueError('取消')
    commands = ['set -e', 'test -z "$(uci changes dhcp)"']
    for section in selected:
        kind, name, target, _ = table[section]
        key, target_key = ('name', 'ip') if kind == 'domain' else ('cname', 'target')
        for field, expected in (('', kind), ('.' + key, parse_uci(snapshot)[section][1]), ('.' + target_key, target)):
            commands.append(f'test "$(uci get dhcp.{section}{field})" = {shlex.quote(expected)}')
    commands += ['backup="$(mktemp /etc/config/dhcp.dns-backup.XXXXXX)"',
                 'cp /etc/config/dhcp "$backup"',
                 'trap \'uci revert dhcp; cp "$backup" /etc/config/dhcp; /etc/init.d/dnsmasq restart\' HUP INT TERM',
                 'trap \'uci revert dhcp\' EXIT']
    commands += [f'uci delete dhcp.{section}' for section in selected]
    commands += ['if ! uci commit dhcp || ! /etc/init.d/dnsmasq restart; then',
                 '  cp "$backup" /etc/config/dhcp; /etc/init.d/dnsmasq restart; exit 1',
                 'fi', 'echo "已删除所选条目；回退备份：$backup"']
    print(run(ssh + ['sh -s'], '\n'.join(commands) + '\n'))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
