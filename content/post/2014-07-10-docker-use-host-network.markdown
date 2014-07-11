+++
draft = false
title = "Docker配置container与host使用同一子网"
date = 2014-07-10T22:18:00Z
tags = [ "docker"]
+++


## 场景

Docker的一般使用场景是在container中运行应用, 然后将应用的端口映射到host的端口上

本文描述的场景是一种特殊的场景, 即container在host的网络上有单独的IP

## 参考

* [Docker Networking Made Simple or 3 Ways to Connect LXC Containers](https://blog.codecentric.de/en/2014/01/docker-networking-made-simple-3-ways-connect-lxc-containers/)


## 步骤

如参考中`Integrate Docker Containers into your Host Network`一节描述的, 让container融入host网络的方法是 将docker在host上使用的bridge的IP修改为host网络的IP.

但此时host上就有两个设备(原设备和bridge)使用同一个网段,造成故障. 需要将原设备的master设为bridge

##### 1. 停掉docker, 删掉原有的bridge `docker0`

```
> service docker stop
> ifconfig docker0 down
> brctl delbr docker0
```

##### 2. 添加新的bridge `bridge0`, 绑定在host网段的ip

```
> brctl addbr bridge0
> ip addr add 192.168.1.99/24 dev bridge0
```

##### 3. 将原设备(设为`eth0`)的master设为`bridge0`

参考上使用的命令是`ip link set eth0 master bridge0`, 但在有些系统上会碰到错误:

```
Error: either "dev" is duplicate, or "master" is a garbage.
```

可以使用

```
> brctl addif bridge0 eth0
```

##### 4. 从原设备`eth0`上卸下原有ip, 启用`bridge0`

```
> ip addr del 192.168.1.99/24 dev eth0
> ifconfig bridge0 up
```

##### 5. 启动docker

```
/usr/bin/docker -d -b=bridge0
```

##### 6. 搞定. 

如果遇到container无法`ping`到其他ip, 记得检查host上的gateway