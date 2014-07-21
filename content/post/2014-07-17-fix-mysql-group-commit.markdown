+++
draft = false
title = "[翻译] Fixing MySQL group commit"
date = 2014-07-17T20:51:00Z
tags = [ "mysql", "group commit"]
+++

###翻译之前

Kristian Nielsen写了Fixing MySQL group commit系列共四篇blog ([第一篇](http://kristiannielsen.livejournal.com/12254.html), [第二篇](http://kristiannielsen.livejournal.com/12408.html), [第三篇](http://kristiannielsen.livejournal.com/12553.html), [第四篇](http://kristiannielsen.livejournal.com/12810.html)). 
读完后对group commit的理解有很大提升, 因此想翻译前三篇, 借此再整理一下自己的思路; 第四篇偏重具体实现, 故不包括

#第一篇

这个系列三篇文章描述了MariaDB是如何支持group commit这个特性的. Group commit是对数据库性能一次重大的提升. 向持久存储里写数据的开销较大, group commit能减轻这种开销对数据库整体性能的影响.

如下图所示, group commit对性能有很大提升:

![引用原文图](http://knielsen-hq.org/maria/fix-group-commit-1.png "引用原文图")

蓝色和黄色的上升线是group commit开启时的TPS, 其对性能改善的程度随着并发交易数的上升而提升


##持久化和group commit

在一个传统交易系统中, 当交易提交成功时, 我们认为交易已经被_持久化(Durable)_了. Durable就是ACID中的D, 其含义是某交易提交成功后, 即使系统在其提交成功后任意时刻崩溃(比如电源故障, 内核崩盘, 服务器软件悲剧, 还有很多很多), 系统重启且从崩溃恢复后, 该交易的状态仍是提交成功的.

确保持久化的通常手段是将足够的信息写入交易日志文件(transactional log file),然后用`fsync()`将数据强制刷到磁盘上, 最后commit操作才成功返回.
凭借这些信息数据库在崩溃重启后能进行完整恢复. 当然除了`fsync`, 刷盘也可以通过`fdatasync()`系统调用或者打开日志文件时用`O_DIRECT`选项, 为了简便, 我们用`fsync()`来代指刷盘操作.

`fsync()`是个昂贵的操作. 传统硬盘(HDD)每秒可以进行150次`fsync()`, 而固态硬盘(比如Intel X25-M)每秒可进行1200次. 如果使用带电cache的RAID控制器, 可以减少`fsync()`带来的性能影响, 但不能完全消除 ([译]我也不太理解这句...).

(除了`fsync()`, 也有其他的手段可以实现持久化. 比如在同步复制的集群(NDB,Galera)里, 假设全部节点不会同时故障, 那交易同步复制到多个节点, 就可以认为交易是持久化的. 
不过不论用什么持久化方法, 较之只提交到本地内存, 持久化的代价要昂贵很多)

如果每个commit都进行`fsync()`, 受限于`fsync()`的成本, 数据库TPS被限制在每秒150个交易(HDD). 
Group commit能改善这个状况. 我们可以用一个`fsync()`来合并多个交易同时发生的刷盘请求. 处理多个交易的刷盘请求, 较之处理一个交易, `fsync()`的成本差别不大, 所以如性能图表所示, 合并刷盘请求能大幅提高性能.

##Group commit in Mysql/MariaDB

Mysql在使用InnoDB存储引擎时可以提供完整的ACID. 对于InnoDB, 开启配置`innodb_flush_log_at_trx_commit=1`时可保证持久性. MariaDB使用XtraDB的情况与之类似.

使用持久化的原因, 一方面是已经提交的事务可以不受系统崩溃的影响, 另一方面, 是可以将数据库作为replication(数据复制)的master(复制源)

replication使用binlog作为手段时, 保证binlog中的数据内容和存储引擎中的数据内容完全一致就很重要. 如果无法保证两者一致, slave(复制目标)将得到和master不一致的数据, 会产生无法估计的影响, 比如在master上进行的SQL无法在slave上成功执行. 
如果不保证持久化, 在系统崩溃时很多数据将丢失, 如果存储引擎中丢失的数据和binlog中丢失的数据不一样多, 那最终两者数据将不一致.
所以, 当使用binlog时, 保证持久化是MySQL/MariaDB能从崩溃正确恢复并达成最终数据一致性的前提.

MySQL/MariaDB 通过XA/binlog和存储引擎的二段提交来保证持久化. 提交一个交易有三个步骤:

1. prepare, 交易在存储引擎上进行持久化(译注: 指的可能是innoDB的undo log). 完成后, 该交易仍可以被回滚. 如之后发生崩溃, 该交易可以被恢复.
2. prepare阶段成功后, 交易在binlog上进行持久化.
3. 最后, commit阶段, 存储引擎将交易真正提交. 完成这步后, 交易将不可被回滚.

当系统崩溃然后重启后, 恢复过程将扫描binlog. binlog中prepare阶段成功但没有commit的交易将进行commit阶段. 其他prepare阶段成功的交易(译注: 不在binlog中的交易)将会被回滚. 以此来保证存储引擎和binlog间的数据一致性.

以上三个步骤中, 每一步骤都需要进行`fsync()`, 相比禁用binlog时一个commit只需调用一次`fsync()`, 这种方式比较昂贵, 使得group commit优化更为重要.

不幸的是当启用binlog时, group commit在MySQL/MariaDB上不能工作! Peter Zaissev在2005年就报了这个著名的[Bug#13669](http://bugs.mysql.com/bug.php?id=13669)

如在开篇的图表和性能测试中所示, 我们在一个数据库服务器上跑了很多小交易(在小XtraDB表上使用REPLACE语句), 对比了启用和禁用binlog的情况. 这种性能测试的瓶颈在于持久化时`fsync()`操作的吞吐量.

我们用了两种不同的服务器来进行性能测试,一种有两块Western Digital 10k rpm HDD存储(binlog和XtraDB log写在不同的存储上); 另一种有一块Intel X25-M SSD存储. 两种服务器都运行MariaDB 5.1.44, 都开启了持久化提交, 也都关闭了存储缓存(否则测试结果将出现偏差).

测试图表表明了不同数量的并发线程下的TPS. 对于每种服务器, 有一条线对应禁用binlog的情况, 另一条线对应开启binlog的情况.

我们看到: 在1个运行线程时, 开启binlog会有一定性能消耗, 原因如我们所料, 是因为一次commit需要调用三次`fsync()`.

更糟糕的是, 在开启binlog时group commit并不工作.随着并发度的增加,  禁用binlog的曲线展现了良好的线性增长的性能, 但开启binlog时的性能曲线则死水一滩. 随着Group commit失效, 高并发时开启binlog的成本高的可怕(HDD存储, 64个并发线程时, 开启binlog将带来两个数量级(大于100倍)的性能损失)

所以第一部分的结论是: 如果我们能在开启binlog时进行group commit优化, 从而解决`fsync()`带来的性能瓶颈, 那么将获得巨大的性能提升.

第二部分将深入探讨为什么开启binlog时group commit的代码会失效. 第三部分将讨论怎样修复这个bug.