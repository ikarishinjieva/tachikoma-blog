+++
draft = false
title = "Q关于nextTick的实现"
date = 2013-01-27T23:00:00Z
tags = [ "Q", "javascript"]
+++

[Q](https://github.com/kriskowal/q) 其中nextTick的一部分是用MessageChannel实现

```
	var channel = new MessageChannel();
	// linked list of tasks (single, with head node)
	var head = {}, tail = head;
	channel.port1.onmessage = function () {
		head = head.next;
		var task = head.task;
		delete head.task;
		task();
	};
	nextTick = function (task) {
		tail = tail.next = {task: task};
		channel.port2.postMessage(0);
	};
```

也有一种实现是用setTimeout(task, 0);

测试下两者的性能区别：[http://jsperf.com/messagechannel-vs-settimeout](http://jsperf.com/messagechannel-vs-settimeout). MessageChannel还是有明显的性能优势

一些额外的参考资料：

[HTML5 web通信（跨文档通信/通道通信）简介 by zhangxinxu](http://www.zhangxinxu.com/wordpress/?p=2229) <有对message和MessageChannel的例子>

[HTML5 Web Messaging](http://www.slideshare.net/miketaylr/html5-web-messaging-7970364) <列举了传统messaging不支持的url pattern，说明了Web Messaging的必要性>