+++
draft = false
title = "False Sharing 阅读"
date = 2013-03-10T23:40:00Z
tags = [ "false_sharing", "performance", "concurrency"]
+++

应该说[这篇](http://ifeve.com/disruptor-cacheline-padding/)和[这篇文章](http://ifeve.com/false-sharing/)是最近读的最有意思的一篇文章，关于多线程访问时，内存预读到寄存器的内容产生的数据竞争(false sharing)对性能的影响(我已经不知道我在说什么了，文章里解释的很清楚)。

重做了第二篇里的试验，发现六个padding不够，需要七个padding(p7)才能有两倍的性能差异。(没有文献里说的那么离谱，测试环境的差异吧)

```
public long p1, p2, p3, p4, p5, p6; // comment out
```

~~TODO：了解第七个padding的来源~~

看了第二篇文章的[更新篇](http://ifeve.com/false-shareing-java-7-cn/), 用这个稳定的代码跑测试，就不会有之前p7的问题。（可能是之前p1-p6被优化掉了？不解。）

在公司八核的机器上也测过，性能提升也就在2-4倍左右。没有那么夸张。

原理基本清楚，对不同平台间的差异完全没想法。不做深入了解。