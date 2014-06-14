+++
draft = false
title = "mysql 5.6.15 replication中碰到的死锁"
date = 2013-10-11T21:21:00Z
tags = [ "mysql", "replication", "deadlock", "bug"]
+++

简述下今天在mysql 5.6.15上碰到的土亢

现象
---

mysql开启主从复制时，用meb（MySQL Enterprise Backup）做备份会卡住。同时在slave上show slave status也会卡住。

查看slave上show processlist，可以看到sql thread的状态为 "Waiting for commit lock"

猜测
---

无论是"SHOW ENGINE INNODB STATUS"还是"SHOW OPEN TABLES"都没有提供有用的信息，还是一切靠猜

夜观天象猜到mysql存在bug ["Another deadlock on FLUSH TABLES WITH READ LOCK + SHOW SLAVE STATUS"](http://bugs.mysql.com/bug.php?id=70307)

其中描述了sql thread开始执行了transaction，但是没有commit的间隙，在slave上FLUSH TABLES WITH READ LOCK，会出现死锁

于是猜测，如果meb恰好在slave上某个transaction commit之前做了FLUSH TABLES WITH READ LOCK，然后调用了与"SHOW SLAVE STATUS"类似的机制获取slave info，那么就会如bug所述卡住。然后mysql由于TABLE LOCk的存在，sql thread也就会卡住。

BTW：搜一下mysql bug库，会有一些描述类似的bug，其中70307描述最靠谱，且有详细的[重现步骤](http://bugs.mysql.com/file.php?id=20542)，我也成功在mysql 5.6.15上重现了bug。

结果
---

实验后证明猜对了...