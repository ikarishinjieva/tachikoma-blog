+++
draft = false
title = "对heartbeat φ累积失败检测算法的学习"
date = 2013-11-05T21:50:00Z
tags = [ "heartbeat", "accrual failure detection", "cluster" ]
+++
偶尔读到了这篇"[φ累积失败检测算法](http://blog.csdn.net/chen77716/article/details/6541968)"，写的非常不错。藉此了解了这个用于heartbeat检测的算法，在此记录一下我自己理解的简单版本

heartbeat时我们使用固定的时间限制t0，当heartbeat的返回时长超过t0时，就认为heartbeat失败。这个方法的弊端是：固定的t0是在事先测定的，不会随网络状况的变化而智能变化。φ累积失败检测算法就是要解决这个问题

失败检验算法的基本思想就是：成功判定“heartbeat失败”的概率符合[正态分布曲线](http://zh.wikipedia.org/wiki/%E6%AD%A3%E6%80%81%E5%88%86%E5%B8%83)，x轴是本次心跳距上次心跳的差距时间，y轴是差距为x的心跳的概率。
<br/>也就是说，假设我们已经有一条正态分布的曲线，当前时间是Tnow，上次心跳成功的时间是Tlast，那么从(Tlast-Tnow) ~ +∞这个区间内的积分（设为w，w<1）就代表某心跳间隔从Tlast维持到大于Tnow的时间的概率，即在Tnow时判定“heartbeat失败”的<b>失败率</b>，就是说如果我们在Tnow这个时间点判定“heartbeat失败”，那么有w的概率我们做出了错误的判定（heartbeat本该是成功的，也许只是被延迟了= =）

臆测这个算法的基本步骤是：

1. 我们假设判定失败率的阈值是<=10%，也就是允许我们判定“heartbeat失败”时最大失败率为10%。
2. 取样本空间，比如前N次心跳的差距时间（心跳接收时间-上次心跳的接收时间）。计算这个样本空间的均值和方差，就可以计算出正态分布曲线
3. 在某时间Tnow，计算(Tlast-Tnow) ~ +∞这个区间内的积分（设为w），即为判定“heartbeat失败”的<b>失败率</b>，若大于阈值10%，则可以判定“heartbeat”失败
4. 重复取样，继续算法

到此基本结束，以下是对原文"[φ累积失败检测算法](http://blog.csdn.net/chen77716/article/details/6541968)"的一些个人补充

* 原文有φ这个变量，主要是因为计算出来的判定失败率可能经常是非常小的小数，所以φ取其负对数，方便比较
* 在此不再重复引用原文的公式

最后，可参考论文[
The φ Accrual Failure Detector](https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=1&cad=rja&ved=0CDEQFjAA&url=http%3A%2F%2Fddg.jaist.ac.jp%2Fpub%2FHDY%2B04.pdf&ei=L_94Uo3OGomciQLCx4GQBg&usg=AFQjCNGYrM_1R5LmY4wrDlKnykatr3VBRA&sig2=G8d5gBsR8MpIwgfU9Xbt7A&bvm=bv.55980276,d.cGE)：

* 这篇论文非常详细（啰嗦）地描述了要解决的问题场景
* 这篇论文给出了一般性的累积失败检测法要满足的特性
* 这篇论文给出了用正态分布曲线来计算的步骤
* 这篇论文给出了算法正确性的比较结果

最后的最后，推荐[这个大牛陈国庆的blog](http://blog.csdn.net/chen77716)，其中文章写的质量高，里面也有对Paxos算法的介绍，配合paxos的wiki，解析的很到位