+++
draft = false
title = "尝试使用mysql plugin将RESET SLAVE后的节点重新恢复成slave"
date = 2014-02-11T22:31:00Z
tags = [ "mysql", "mysql plugin", "replication"]
+++

这几天在尝试为以下场景制作一个mysql plugin, 但是是一个失败的尝试, 在此记录

场景
---

    一对mysql主从节点 M-S, 节点S执行了RESET SLAVE
    后来后悔了
    在没有数据通过非replication的渠道写入S的条件下, 想让S和M重新恢复成一对主从

关键点是S能将`RESET SLAVE`时S的`Exec_Master_Log_Pos`和`S binlog pos`记录下来

尝试了以下几种方案:

调用者在`RESET SLAVE`时手工记录, 不需要制作插件
----

Audit plugin. 
---

Mysql的Audit plugin可以审计大部分mysqld经手的SQL, 包括`RESET SLAVE`.

但Audit plugin是在每个SQL之后才会调用. 在`RESET SLAVE`时S上master_info会被清理, 即`Exec_Master_Log_Pos`的信息在调用Audit plugin已经丢失

Replication plugin (`after_reset_slave`)
---

Replication plugin (参看mysql semisync的源码), 在slave端提供了`Binlog_relay_IO_observer`, 贴个Mysql源码方便理解

    /**
        Observes and extends the service of slave IO thread.
     */
     typedef struct Binlog_relay_IO_observer {
       uint32 len;
     
       /**
          This callback is called when slave IO thread starts
     
          @param param Observer common parameter
     
          @retval 0 Sucess
          @retval 1 Failure
       */
       int (*thread_start)(Binlog_relay_IO_param *param);
     
       /**
          This callback is called when slave IO thread stops
     
          @param param Observer common parameter
     
          @retval 0 Sucess
          @retval 1 Failure
       */
       int (*thread_stop)(Binlog_relay_IO_param *param);
     
       /**
          This callback is called before slave requesting binlog transmission from master
     
          This is called before slave issuing BINLOG_DUMP command to master
          to request binlog.
     
          @param param Observer common parameter
          @param flags binlog dump flags
     
          @retval 0 Sucess
          @retval 1 Failure
       */
       int (*before_request_transmit)(Binlog_relay_IO_param *param, uint32 flags);
     
       /**
          This callback is called after read an event packet from master
     
          @param param Observer common parameter
          @param packet The event packet read from master
          @param len Length of the event packet read from master
          @param event_buf The event packet return after process
          @param event_len The length of event packet return after process
     
          @retval 0 Sucess
          @retval 1 Failure
       */
       int (*after_read_event)(Binlog_relay_IO_param *param,
                               const char *packet, unsigned long len,
                               const char **event_buf, unsigned long *event_len);
     
       /**
          This callback is called after written an event packet to relay log
     
          @param param Observer common parameter
          @param event_buf Event packet written to relay log
          @param event_len Length of the event packet written to relay log
          @param flags flags for relay log
     
          @retval 0 Sucess
          @retval 1 Failure
       */
       int (*after_queue_event)(Binlog_relay_IO_param *param,
                                const char *event_buf, unsigned long event_len,
                                uint32 flags);
     
       /**
          This callback is called after reset slave relay log IO status
          
          @param param Observer common parameter
     
          @retval 0 Sucess
          @retval 1 Failure
       */
       int (*after_reset_slave)(Binlog_relay_IO_param *param);
     } Binlog_relay_IO_observer;
     
首先尝试用`after_reset_slave`, 从函数名字就可以看到会遇到和Audit Plugin相同的问题: 即`Exec_Master_Log_Pos`的信息在调用时已经丢失


Replication plugin (`after_reset_slave`再尝试, `future_group_master_log_pos`)
---

还不死心, `Exec_Master_Log_Pos`的数据结构是`Relay_log_info.group_master_log_pos`, 尽管这个信息在`after_reset_slave`时已经丢失, 但发现`Relay_log_info.future_group_master_log_pos`可能是个方向

先解释`Relay_log_info.future_group_master_log_pos`, 可以参看`log_event.cc`的这段注释

      /*
        InnoDB internally stores the master log position it has executed so far,
        i.e. the position just after the COMMIT event.
        When InnoDB will want to store, the positions in rli won't have
        been updated yet, so group_master_log_* will point to old BEGIN
        and event_master_log* will point to the beginning of current COMMIT.
        But log_pos of the COMMIT Query event is what we want, i.e. the pos of the
        END of the current log event (COMMIT). We save it in rli so that InnoDB can
        access it.
      */
      const_cast<Relay_log_info*>(rli)->future_group_master_log_pos= log_pos;
      
`future_group_master_log_pos`指向了execute的最后一个transaction的COMMIT event之前, 即`future_group_master_log_pos` 大部分时间等于 `group_master_log_pos - 27` (27是COMMIT event的长度)

但仍有例外情况: 如果M执行了`FLUSH LOGS`, 将log从0001递增到了0002, 此时S上的`future_group_master_log_pos`会指向0001的最后一个transaction的COMMIT event之前. 但S上的`group_master_log_name`已经到了0002, 与`future_group_master_log_pos`不匹配, 会引起异常

(其实此时S上的`group_master_log_name`也已经置空了, 但可以从内存残片中恢复出文件名)

设想如果对于log_name也有`future_group_master_log_name`, 那么S可以直接`change master`到M的`future_group_master_log_name`和`future_group_master_log_pos`位置, 可以恢复起M-S主从结构

Replication plugin (`thread_stop`)
---

Replication plugin的`thread_stop`是指Slave IO thread停止时调用, 此时可以拿到`Exec_Master_Log_Pos`和`S binlog pos`, 但拿到的`S binlog pos`没有意义, 因为不能保证Slave SQL thread也停下来了

Storage Engine plugin
---

这是我最后一根救命稻草, 阅读Mysql源码时注意到以下片段(做了缩减)

    int reset_slave(THD *thd, Master_info* mi)
    {
        ...
        ha_reset_slave(thd);
        ... //clean memory data
    }

`reset_slave`在清理内存数据前通知了storage engine插件, 这个插件可以获得所有必要信息

但存在一个问题, 即`ha_reset_slave`仅在Mysql NDB版本中存在, 不具备通用性, 参看宏定义(做了缩减)

    #ifdef HAVE_NDB_BINLOG
    ...
    void ha_reset_slave(THD *thd);
    ...
    #else
    ...
    #define ha_reset_slave(a) do {} while (0)
    ...
    #endif
    

吐槽和总结
---

可以看到Mysql plugin不**太**预留接口, 是仅仅为已知应用场景提供必要接口, 比如`Binlog_relay_IO_observer`中有`after`不一定有`before`. 比较容易控制插件质量, 但插件能做到的非常局限.

以上各种尝试, 归根到底, 只要修改Mysql的一点源码编译一下就可以达到很好的效果, 不需要用插件的方式在Mysql中到处找功能插槽, 但通用性变差.