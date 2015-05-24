+++
draft = false
title = "golang 查询 /proc/self/exe 失败或 Setgroups() 失效"
date = 2015-05-24T23:51:00Z
tags = [ "golang" ]
+++

前一段时间发生了些很奇怪的现象:

1. 在程序入口的第一句使用`Readlink("/proc/self/exe")`, 有小概率报出permission denied
2. 使用`Setgroups()`进行用户组设置, 但之后的操作中随机概率用户组设置会失效

这两个问题困扰了蛮久, 第一个问题一直没找到描述问题的合适的关键字, 第二个问题没往系统的方向上想, 而是一直在检查程序逻辑的错误. `strace`和coredump也没有提供有用的信息.

直到有一天晚上一位同事提醒我`man proc(5)`中有这样一段话: 

```
In a multithreaded process, the contents of this symbolic link are not available if the main thread has already terminated (typically by calling pthread_exit(3)).
```

这就通了, 这两个问题都可能由于golang将执行块调度到了另外的线程上引起的. 

在uid/gid相关的man文档里, 相关的描述如下:

```
At the kernel level, user IDs and group IDs are a per-thread attribute.
```

解决方法是利用golang的`runtime.LockOSThread()`, 使用的形式参看[go-wiki](https://code.google.com/p/go-wiki/wiki/LockOSThread). 

还有一个[相关的issue](https://github.com/golang/go/issues/1435).

一开始的思考方向偏了, 没找到正确的问题关键字, 着实浪费了一些时间.