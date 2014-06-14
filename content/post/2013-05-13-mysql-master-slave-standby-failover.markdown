+++
draft = false
title = "实验：Mysql master-slave-standby将source从master切换到standby"
date = 2013-05-15T22:40:00Z
tags = [ "mysql", "replication"]
+++

尝试了&lt;Mysql High Availability&gt;第四章热备份一节的实验,记录步骤.

先统一原语,master/slave/standby表示三台机器名,source/target代表replication关系的两端（不适用master/slave用以和机器名区分）."master(3)"表示master机器的db里有三条数据1,2,3.

实验开始.

.1. 初始状态是存在master->slave, master->standby的replication
.2. standby在切换成source时,需要有bin-log和replication user. 在此重新设置master->standby的replication, 让standby满足要求. 

忽略replication user的部分. 

bin-log的部分在my.cnf里要设置log-bin和log-slave-updates(默认情况下,master->standby的replication不会写standby的bin-log,需开始standby的log-slave-updates才会写).


```
server-id               = 3
log_bin                 = /var/log/mysql/mysql-bin.log
...
relay-log-index         = /var/log/mysql/slave-relay-bin.index
relay-log               = /var/log/mysql/slave-relay-bin
log-slave-updates
```

.3. 测试一下standby binlog设置成功。可以在master插入一条数据，在standby查看

```
standby> show binlog events;
+------------------+------+-------------+-----------+-------------+------------------------------------------------------------------------+
| Log_name         | Pos  | Event_type  | Server_id | End_log_pos | Info                                                                   |
+------------------+------+-------------+-----------+-------------+------------------------------------------------------------------------+
| mysql-bin.000001 |    4 | Format_desc |         3 |         107 | Server ver: 5.5.31-0ubuntu0.12.04.1-log, Binlog ver: 4                 |
| mysql-bin.000001 |  107 | Query       |         1 |         166 | BEGIN                                                                  |
| mysql-bin.000001 |  166 | Query       |         1 |         257 | use `tac`; insert into test values(8889)                               |
| mysql-bin.000001 |  257 | Xid         |         1 |         284 | COMMIT /* xid=111 */    
...
```

.4. 将replication调整至状态master(3),standby(2),slave(1). 人工造成各db的状态不一致

```
master> insert into test values(1);
slave> stop slave;
master> insert into test values(2);
standby> stop slave;
master> insert into test values(3);
```

.5. 想象此时master挂掉,开始将source从master切换成standby

.6. 在建立standby->slave的replication之前，需要将standby和slave数据同步(此时slave落后于standby)。

```
-- 先查看standby从master拿了多少数据
standby> show slave status \G
*************************** 1. row ***************************
...
        Master_Log_File: master-bin.000023
...
        Exec_Master_Log_Pos: 1391
		  
-- 让slave从master上同步到跟standby同样的位置
slave> start slave until master_log_file = 'master-bin.000023', master_log_pos = 1391;
```

有意思的是此处用了master(其实我们假设master已经坏了...)。

.7. 此时可以讲slave的source从master切换到standby. 一个问题就是standby->slave的开始位置可能是和master->slave不同

```
-- 查看standby binlog的当前位置
mysql> show master status \G
*************************** 1. row ***************************
    File: mysql-bin.000001 
    Position: 796
    Binlog_Do_DB:
	Binlog_Ignore_DB:
-- 注意与master上的文件名和位置都不同

-- 切换slave的source
slave> change master to 
			  master_host = '192.168.50.4', 
			  master_port = 3306, 
			  master_user = 'repl', 
			  master_password = 'repl', 
			  master_log_file = 'mysql-bin.000001', 
			  master_log_pos = 796;
```

.8. 测试一下standby->slave replication.

总的思路就是讲master(3),standby(2),slave(1)同步成master(3),standby(2),slave(2),然后将master->slave切换成standby->slave.

遗留了两个问题,其一是slave和standby同步时使用了"坏掉"的master;其二是master超前了standby和slave, 也就是standby->slave丢失了master的超前数据。留待慢慢学习。