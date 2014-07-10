+++
draft = false
title = "初次使用Docker碰到的一些问题"
date = 2014-07-10T22:53:00Z
tags = [ "docker"]
+++

初次使用docker, 确实是好东西, 但也碰到一些乱七八糟的错, 记录一下

### iptables不可用

在container内部使用iptables会碰到如下错误

```
bash-4.1# /etc/init.d/iptables status

Table: filter
FATAL: Could not load /lib/modules/2.6.32-358.el6.x86_64/modules.dep: No such file or directory
iptables v1.4.7: can't initialize iptables table `filter': Permission denied (you must be root)
Perhaps iptables or your kernel needs to be upgraded.
Table: nat
FATAL: Could not load /lib/modules/2.6.32-358.el6.x86_64/modules.dep: No such file or directory
iptables v1.4.7: can't initialize iptables table `nat': Permission denied (you must be root)
Perhaps iptables or your kernel needs to be upgraded.
```

查了很久, 发现docker在其[blog](http://blog.docker.com/2013/08/containers-docker-how-secure-are-they/)中深藏了其原因 (`Linux Kernel Capabilities`一节)

解决方法是在启动container时加入参数`--privileged=true`, 来开启被禁用的能力

### `--privileged=true` 遇到错误

在使用`docker run --privileged=true ...` 时遇到错误

```
Error: Cannot start container f4468e2ddd314c572582f2c96022a56e4c45383897495ac117167fa3b4702ed6: stat /dev/.udev/db/bsg:2:0:0:0: no such file or directory
```

这是一个docker 1.0.0的bug, 可以在github的bug列表中找到. 解决方案就很简单, 升级docker到1.1.0就可以

但docker的编译过程会使用`--privileged=true`这个参数, 导致没法编译docker 1.1.0

幸好docker提供了binary下载, 直接下载1.1.0的binary, 替换`/usr/bin/docker`就可以了

