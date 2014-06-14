+++
draft = false
title = "jruby重写java项目的一些总结"
date = 2013-08-29T21:22:00Z
tags = [ "jruby", "java", "dsl"]
+++
久不更新了，6月换了工作

最近将一个小项目从java迁移到了jruby，在此总结一下

从结果开始
---

.1.代码量上的比较

| *        		| 纯Java项目 	| Jruby项目 	 |
| ------------- | ------------- | ---------- |
| 主代码行数		| 4073			| 2689 - 454 |
| 测试代码行数	| 1707			| 1485 - 319 |

其中Jruby项目中有454行主代码和319行测试代码为新加功能

结论是在迁移了所有功能后，主代码量减少了45%+，测试代码比例从41%增加到52%，测试case数也增加

.2.DSL

在迁移过程中，加入了一些DSL，让代码变得更可读，类似于

```
unless can_load local_node.config.from_file
	load local_node.config, :sip_ip
	cluster.join local_node.config.sip_ip
	cluster.lock "lock_config" do
		load_remote_global_config
		load local_node.config, with(@remote_global_config)
		dump local_node.config
	end
else
```

如果了所有符号，就变成稍微(!)可读的一篇描述

.3.部署

jruby可以被编译成class，打成jar，跑在一切有jvm和jruby jar的地方。与现有java项目的融合不成问题，此次也是迁移了整个项目中的一部分，其他部分保留java

一些细节
---

.1.代码量的减少

抛弃脚本语言的优势论不谈，实践中，代码量的明显减少来自于以下几个方面：

   1.1.调用命令行更方便，在纯java中调用命令行比较烦，即使封装半天也很不爽。代码量差别不是很大，主要是不爽

   1.2.闭包。java中传递闭包得靠实现匿名接口，冗长麻烦，影响函数的复用。（要不定义多个函数，要不到处new interface）

   1.3.mixin。奇怪的是我混入的往往不是特性，而是辅助函数... 尽管这种方法不正规，但对于小类来说非常实用。比较以下两段代码

```
class A
	def aaaa
		XxxUtils.blabla ...
		YyyHelper.blublu ...
	end
end
```

```
class A
	include XxxUtils, YyyHelper
	def aaaa
		blabla ...
		blublu ...
	end
end
```

   如果你跟我一样厌恶到处都是Utils、Helper，又比较烦static import...

   "mixin太多很容易命名冲突引起问题"，不得不承认这个担心是对的，我爽我的，谁爱操心谁操心吧。顺便提一句，名空间冲突解决最好的方法还数node.js的。

   1.4.标准库。不得不承认，ruby标准库的人性化做的非常好，链调用能节省很多无用的代码

   1.5.rspec mock。以前用java尽量避免用mock framework，都是用继承注入，太费代码以至于自己都觉得烦（尽管有IDEA的自动代码折叠，还是觉得烦），到处都是注入点的代码也很乱。
   这是一个很难解决的平衡，如果每一段代码都是上下文封闭的，那么代码很容易测试，但处理输入输出需要大量工作，如果不是，那测试就需要mock。
   尝试了rspec mock后（我相信任何mock framework都一样），觉得还不错，目前还没有失控的主要原因是每次mock不超过两层。

   最后，"代码行数不是XXX标准"，是的，我只是减少了无用代码元素在项目中的分布

.2.DSL/HSL(Human-specific language)

关于DSL的尝试还很初级，主要目的是读起来通顺，拘泥于以下几种形式：

   2.1.函数名alias。每次写代码的时候是不是纠结于用[].exist、[].exists，或者[].exists?。实践中都是先流畅的（！）写函数梗概，不纠结调用的函数是不是存在，爱怎么用怎么用吧，不存在就alias一下。一切以写作顺畅为目的。

   2.2.mixin。如前面提到的，mixin提供了忽略类名的偏门，可以写出一句流畅的人话，比如cp file，而不是FileUtils.cp file

   2.3.动词函数。比较array.collect和collect array，我喜欢后面那款。动词函数，让"宾.动"的OO非人话，转换成"动宾"的人话。当然除非你是古文爱好者

   2.4."介词"空函数。就是些输出=输入的空函数，比如之前例中"unless can_load local_node.config.from_file"的can_load就是空函数，较之"unless local_node.config.load_from_file?"更有人味

   2.5.最后，以上几种形式都没有Domain-specific，而是Human-specific。关于DSL的尝试还没有深入到domain的阶段，先从让程序说人话开始

   2.6.难以否认的部分：像所有的城市规划一样，整洁的背后都会藏着付出代价的区域，DSL的背后也会有支持代码，初次读支持代码会发现他们怪异、畸形、目的非常不明确，配合用例才能读懂。
   如何更好的管理这部分付出牺牲的代码值得讨论

.3.部署和测试

简单描述一下当前部署方案中的要点

   3.1.跑测试时不用编译，直接跑rb脚本。部署时才编译。可以节省测试时间。

   3.2.程序运行是用java -cp .../jruby.jar com.xxx.XXX。测试运行是用java -cp .../jruby.jar org.jruby.Main -S blabla

   3.3.GEM_HOME 和 GEM_PATH 指向特定folder，用上面的命令安装gem即可将gem安装到指向的folder

   3.4.编译用jrubyc，打jar包的脚本需要自己写

   PS: 写个简单的watchr脚本，可以让主文件和相应的测试文件保存时，自动跑相应的测试，非常省事

.4.一些缺陷

不得不承认的缺陷还有很多

   4.1.不是所有项目能平滑接入jruby，之前的确碰到过jruby和EclipseLink的冲突，与boot classpath相关，具体原因不祥。建议迁移前先搭原型进行测试

   4.2.（这条来自于实践经验）HSL(Human-specific language) 不是能全面实现的，只能在程序里的一部分实现，而且随着代码量的增加，支持代码的维护估计会显得吃力。（但是写起来的确很爽）

   4.3.改进后的代码也不是完全可读，难以忽略一些语言元素，也没法忽略业务背景

   4.4.写单元测试吧，懒不是个办法...