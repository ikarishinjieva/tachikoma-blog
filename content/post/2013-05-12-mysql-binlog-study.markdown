+++
draft = false
title = "关于Mysql binlog的一点学习"
date = 2013-05-12T22:59:00Z
tags = [ "mysql", "binlog", "replication"]
+++

差不多一个月没更新了。除了忙些琐事，就是偷点懒。

在读&lt;Mysql High Availability&gt;，扫了一遍，读第二遍的时候开始做些实验，所以这之后的blog写的也会没什么章法。

&lt;Mysql High Availability&gt;第三章介绍binlog时特地提到了Rand()/Now()/User variable/Password()在基于sql复制时的行为，简单做些实验。

Rand()
---

Rand() 在replication中，值会被正确传递。如下查看binlog，发现pos 209处rand_seed会被传给slave，保证rand生成的值保持一致。

```
mysql> show binlog events in 'master-bin.000007';
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
| Log_name          | Pos | Event_type  | Server_id | End_log_pos | Info                                                   |
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
| master-bin.000007 |   4 | Format_desc |         1 |         107 | Server ver: 5.5.31-0ubuntu0.12.04.1-log, Binlog ver: 4 |
| master-bin.000007 | 107 | Query       |         1 |         174 | BEGIN                                                  |
| master-bin.000007 | 174 | RAND        |         1 |         209 | rand_seed1=598597315,rand_seed2=24268577               |
| master-bin.000007 | 209 | Query       |         1 |         302 | use `tac`; insert into test values(rand())             |
| master-bin.000007 | 302 | Xid         |         1 |         329 | COMMIT /* xid=151 */                                   |
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
```

Now()
---

Now() 在replication中，值会被正确传递。如下查看binlog，pos 283处，貌似这个语句传给slave，会由于master和slave的时间不同步，导致问题。

```
     master> flush logs;
     master> SET TIMESTAMP=unix_timestamp('2010-10-01 12:00:00');
     master> insert into test values(now());
     master> show binlog events in 'master-bin.000007';

+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
| Log_name          | Pos | Event_type  | Server_id | End_log_pos | Info                                                   |
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
| master-bin.000012 |   4 | Format_desc |         1 |         107 | Server ver: 5.5.31-0ubuntu0.12.04.1-log, Binlog ver: 4 |
| master-bin.000012 | 107 | Query       |         1 |         182 | BEGIN                                                  |
| master-bin.000012 | 182 | Query       |         1 |         283 | use `tac`; insert into test values (now())             |
| master-bin.000012 | 283 | Xid         |         1 |         310 | COMMIT /* xid=131 */                                   |
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
```

但通过mysqladmin查看binlog，可以看到binlog中会不断插入TIMESTAMP来保证now()函数的执行结果在master和slave是相同的。

```
master> sudo mysqlbinlog --short-form master-bin.000017
... 
DELIMITER /*!*/;
SET TIMESTAMP=1285934400/*!*/;
...
BEGIN
/*!*/;
use `tac`/*!*/;
SET TIMESTAMP=1285934400/*!*/;
insert into test values(now())
/*!*/;
COMMIT/*!*/;
SET TIMESTAMP=1368372377/*!*/;
BEGIN
/*!*/;
SET TIMESTAMP=1368372377/*!*/;
insert into test values(now())
/*!*/;
COMMIT/*!*/;
...
```

User variable
---

User variable会被编码成十六进制串，含义不明，保密性不明。

```
mysql> flush logs;
Query OK, 0 rows affected (0.02 sec)

mysql> set @foo = now();
Query OK, 0 rows affected (0.00 sec)

mysql> insert into test values (@foo);
Query OK, 1 row affected (0.01 sec)

mysql> show binlog events in 'master-bin.000014';
+-------------------+-----+-------------+-----------+-------------+-----------------------------------------------------------------------------------+
| Log_name          | Pos | Event_type  | Server_id | End_log_pos | Info                                                                              |
+-------------------+-----+-------------+-----------+-------------+-----------------------------------------------------------------------------------+
| master-bin.000014 |   4 | Format_desc |         1 |         107 | Server ver: 5.5.31-0ubuntu0.12.04.1-log, Binlog ver: 4                            |
| master-bin.000014 | 107 | Query       |         1 |         174 | BEGIN                                                                             |
| master-bin.000014 | 174 | User var    |         1 |         229 | @`foo`=_latin1 0x323031302D31302D30312031323A30303A3030 COLLATE latin1_swedish_ci |
| master-bin.000014 | 229 | Query       |         1 |         321 | use `tac`; insert into test values (@foo)                                         |
| master-bin.000014 | 321 | Xid         |         1 |         348 | COMMIT /* xid=148 */                                                              |
+-------------------+-----+-------------+-----------+-------------+-----------------------------------------------------------------------------------+
5 rows in set (0.00 sec)
```

Password()
---

直接内嵌使用password，会在binlog里暴露密码，就像下面的测试。可以使用user variable,但是不知道user variable的编码保密性如何。

```
mysql> insert into test values(password('tac'));
mysql> show binlog events in 'master-bin.000015';
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
| Log_name          | Pos | Event_type  | Server_id | End_log_pos | Info                                                   |
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
| master-bin.000015 |   4 | Format_desc |         1 |         107 | Server ver: 5.5.31-0ubuntu0.12.04.1-log, Binlog ver: 4 |
| master-bin.000015 | 107 | Query       |         1 |         174 | BEGIN                                                  |
| master-bin.000015 | 174 | Query       |         1 |         276 | use `tac`; insert into test values(password('tac'))    |
| master-bin.000015 | 276 | Xid         |         1 |         303 | COMMIT /* xid=158 */                                   |
+-------------------+-----+-------------+-----------+-------------+--------------------------------------------------------+
4 rows in set (0.01 sec)
```

简单一点学习如上。