+++
draft = false
title = "测试Mysql 5.5的crash safe"
date = 2014-08-17T19:13:00Z
tags = [ "mysql", "crash safe", "debug"]
+++

事情的起因有点意思, 前几天QA在参照[文档](http://bugs.mysql.com/bug.php?id=69444)测试Mysql 5.6的crash safe特性. QA读到了源码里面的一段:

```
  if ((error= w->commit_positions(this, ptr_group,
                                  w->c_rli->is_transactional())))
    goto err;

...

  DBUG_EXECUTE_IF("crash_after_update_pos_before_apply",
                  sql_print_information("Crashing crash_after_update_pos_before_apply.");
                  DBUG_SUICIDE(););

  error= do_commit(thd);
```

并用`crash_after_update_pos_before_apply`选项成功复现了bug.

后来QA问我Mysql 5.5怎么测试crash safe, 因为她注意到Mysql 5.5的代码里并没有类似的测试插桩.

读过Mysql 5.5的源码后, 找到了下面的位置

```
int apply_event_and_update_pos(Log_event* ev, THD* thd, Relay_log_info* rli) {
    if (reason == Log_event::EVENT_SKIP_NOT)
    exec_res= ev->apply_event(rli);
    ...
    //插入代码的位置
    if (exec_res == 0) {
        int error= ev->update_pos(rli);
        ...
    }
}
```

在标记的位置插入代码`DBUG_EXECUTE_IF("crash_after_apply_log_and_before_update_pos", DBUG_SUICIDE(););`, 重新编译Mysql就可以用`crash_after_apply_log_and_before_update_pos`作为debug选项了.