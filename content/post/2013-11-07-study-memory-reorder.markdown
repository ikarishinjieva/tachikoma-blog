+++
draft = false
title = "对Memory Reordering Caught in the Act的学习"
date = 2013-11-07T21:40:00Z
tags = [ "memory" ]
+++

最近迷上了preshing.com，真的是非常专业的blog，每篇深浅合适而且可以相互印证，达到出书的质量了

学习了[Memory Reordering Caught in the Act](http://preshing.com/20120515/memory-reordering-caught-in-the-act/)，内容很简单，主要是说“即使汇编码是顺序的，CPU执行时会对Load-Save进行乱序执行，导致无锁的两线程出现意料之外的结果”

简述一下：

* 首先我们有两个线程，Ta和Tb，且有四个公共变量，a,b,r1,r2
* Ta的代码是 a=1, r1=b
* Tb的代码是 b=1, r2=a
* 保证编译器不做乱序优化
* 由于两个线程的读都在写之后，那么理论上，r1和r2中至少有一个应为1，或者都为1
* 但实际并非如此

原因是CPU会做乱序执行，因为Ta/Tb的代码乱序后，比如r1=b, a=1，从单线程的角度来看对结果没有影响。而对于多线程，就会出现r1=r2=0的状况

解决方案是在两句之间插入Load-Save fence，参看[这里](http://preshing.com/20120710/memory-barriers-are-like-source-control-operations/)

我自己用go想重现这个场景，代码参看最后。但是奇怪的是go的编译码跟文章描述的差不多

```
    [thread 1]
    ...
    MOVQ    $1,a+0(SB)
    MOVQ    b+0(SB),BX
    MOVQ    BX,r1+0(SB)
    
    [thread 2]
    MOVQ    $1,b+0(SB)
    MOVQ    a+0(SB),BX
    MOVQ    BX,r2+0(SB)
```
    
但是在MBP (Intel Core i7)上跑并没有出现CPU乱序的现象，希望有同学能帮我提供线索，谢谢

(2013.11.11 更新：关于以上现象的原因参看[续 - 关于go的部分](http://ikarishinjieva.github.io/blog/blog/2013/11/11/study-memory-reorder-cont/))

go 代码：

```
    package main
    
    import (
    	"fmt"
    	"math/rand"
    )
    
    var x, y, r1, r2 int
    var detected = 0
    
    func randWait() {
    	for rand.Intn(8) != 0 {
    	}
    }
    
    func main() {
    	beginSig1 := make(chan bool, 1)
    	beginSig2 := make(chan bool, 1)
    	endSig1 := make(chan bool, 1)
    	endSig2 := make(chan bool, 1)
    	go func() {
    		for {
    			<-beginSig1
    			randWait()
    			x = 1
    			r1 = y
    			endSig1 <- true
    		}
    	}()
    	go func() {
    		for {
    			<-beginSig2
    			randWait()
    			y = 1
    			r2 = x
    			endSig2 <- true
    		}
    	}()
    	for i := 1; ; i = i + 1 {
    		x = 0
    		y = 0
    		beginSig1 <- true
    		beginSig2 <- true
    		<-endSig1
    		<-endSig2
    		if r1 == 0 && r2 == 0 {
    			detected = detected + 1
    			fmt.Println(detected, "reorders detected after ", i, "iterations")
    		}
    	}
    }
```