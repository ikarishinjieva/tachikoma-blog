+++
draft = false
title = "jruby中tcp阻塞时Timeout::timeout失效"
date = 2014-01-08T23:04:00Z
tags = [ "jruby", "tcp", "bug"]
+++

问题场景
---

首先有一台tcp server, 模拟一个黑洞

```
require 'socket'

tcp_server = TCPServer.new("0.0.0.0", 6666)

loop do
     socket = tcp_server.accept
     puts 'got conn']
     #blackhole
end
```

然后发起一个connection, 从server接受消息(很显然会阻塞在recv上), 并用`Timeout::timeout`设置一个超时时间

```
require "socket"
require "timeout"

sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
addr = Socket.sockaddr_in(6666, "127.0.0.1")
sock.connect(addr)

Timeout::timeout(5) {
     sock.recv(1)
} 
```

上面这个场景如果在ruby上跑,5秒后会超时,但如果使用jruby(1.7.6)就会一直处于阻塞

解决方案
---

使用非阻塞`recv`,可以在jruby上正常运行

```
require "socket"
require "timeout"

sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
addr = Socket.sockaddr_in(6666, "127.0.0.1")
sock.connect(addr)

Timeout::timeout(5) {
    begin
        sock.recv_nonblock(1)
    rescue IO::WaitReadable
        IO.select([sock],nil,nil,5)
        retry
    end
} 
```

猜测
---

查看一下ruby `timeout.rb`的源码

```
  begin
    x = Thread.current
    y = Thread.start {
      begin
        sleep sec
      rescue => e
        x.raise e
      else
        x.raise exception, "execution expired"
      end
    }
    return yield(sec)
  ensure
    if y
      y.kill
      y.join # make sure y is dead.
    end
  end
```

大概看到timeout是起了一个计时线程,超时时向主线程发起exception

猜测是因为jvm的线程模型导致exception不能向阻塞线程提交,但有待验证

