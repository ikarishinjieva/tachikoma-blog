+++
draft = false
title = "jruby backtick + jre 6 会卡住"
date = 2013-10-11T22:03:00Z
tags = [ "jruby", "jre", "bug"]
+++

最近在jruby 1.7.5 + jre 6上碰到的土亢

现象
---

用backtick调用命令，比如`./some_script`

在调用命令之前/同时在terminal输入一些回车，有一定概率backtick的调用会卡住不返回。
此时再输入一个回车，调用会继续执行并返回。

解决
---

一切靠猜

jruby有个bug：[Gaps in STDIN pipe stream if backtick is used](http://jira.codehaus.org/browse/JRUBY-4626)

Charles Oliver Nutter在comment中写到"For JRuby 1.7pre1 on Java 7, this should be fixed; TTY should be handled correctly. For other Java versions, we can't fix this."，于是最方便的就是升级jre到7

经验证升级jre可以从土亢中爬出来。
如果难以升级jre，参看[这里](https://www.ruby-forum.com/topic/4413754)，这个兄弟做了很全的测试。可以用IO.popen或者Open3.popen3替换backtick。

经验
---

jruby有坑，同时也提供了便捷的手段将现有的java项目改成比较爽的样子。这些坑是难以预料的，做好准备，然后一如既往踩过去。