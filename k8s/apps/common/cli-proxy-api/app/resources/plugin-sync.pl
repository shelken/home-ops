#!/usr/bin/perl
# postStart: 宿主就绪后, 按 config.yaml 声明的插件版本对齐宿主实际注册状态。
# 已注册且版本一致的插件直接跳过, 其余交给宿主自己的 plugin-store install 接口,
# 下载/校验/落盘/注册全部由 CPA 原生完成。
#
# 容器生命周期钩子会阻塞容器进入 RUNNING, 且钩子失败会终止容器; 因此这里先 fork
# 到后台再立即退出, 同步失败只影响日志, 不影响 CPA 自身启动。
use strict;
use warnings;
use POSIX ();
use IO::Socket::INET;

if (my $pid = fork()) {
    exit 0;
}
POSIX::setsid();

# exec 钩子的输出不进容器日志, 改写到 PID 1(CPA) 的 stdout/stderr 才能被 kubectl logs 看到
open STDOUT, ">>", "/proc/1/fd/1" or exit 0;
open STDERR, ">>", "/proc/1/fd/2" or exit 0;
$| = 1;

my $host = "127.0.0.1:8317";
my $key  = $ENV{MANAGEMENT_PASSWORD};

sub request {
    my ($method, $path) = @_;
    my $sock = IO::Socket::INET->new(PeerAddr => $host, Proto => "tcp", Timeout => 180) or return;
    print $sock "$method $path HTTP/1.0\r\nHost: $host\r\n"
        . "Authorization: Bearer $key\r\nContent-Length: 0\r\n\r\n";
    my $res = "";
    while (<$sock>) { $res .= $_ }
    close $sock;
    return $res =~ m{HTTP/1\.[01] 200} ? $res : undef;
}

# config.yaml 里 plugins.configs.<id>.store.version 即期望版本
sub declared_plugins {
    my ($path) = @_;
    open my $cfg, "<", $path or return ();
    my ($id, @want);
    while (my $line = <$cfg>) {
        $id = $1 if $line =~ /^ {4}([a-z0-9_-]+):\s*$/;
        push @want, [ $id, $1 ] if defined $id && $line =~ /^\s+version:\s*(\S+)\s*$/;
    }
    close $cfg;
    return @want;
}

# 与主进程并发, 宿主可能还没监听
my $plugins;
for (1 .. 60) {
    $plugins = request("GET", "/v0/management/plugins");
    last if defined $plugins;
    sleep 1;
}
exit 0 unless defined $plugins;

for my $item (declared_plugins("/config/config.yaml")) {
    my ($id, $version) = @$item;
    if ($plugins =~ /"id":"\Q$id\E"(.*?)(?="id":"|\z)/s) {
        my $entry = $1;
        next if $entry =~ /"registered":true/ && $entry =~ /"version":"\Q$version\E"/;
    }
    my $res = request("POST", "/v0/management/plugin-store/$id/install?version=$version");
    print $res ? "plugin ready: $id $version\n" : "plugin install failed: $id $version\n";
}

exit 0;
