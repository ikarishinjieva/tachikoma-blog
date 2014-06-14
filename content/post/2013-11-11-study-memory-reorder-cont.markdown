+++
draft = false
title = "对Memory Reordering Caught in the Act的学习 续 - 关于go的部分"
date = 2013-11-11T20:44:00Z
tags = [ "memory", "go"]
+++

这篇主要解决[上一篇](http://ikarishinjieva.github.io/blog/blog/2013/11/07/study-memory-reorder/)遗留下来的问题，问题的简要描述请参看[我发在SO上的帖子](http://stackoverflow.com/questions/19901615/why-go-doesnt-show-memory-reordering)

主要的问题是用c++可以重现memory reordering，但go的程序没有重现

主要的结论是写go的时候我忘记设置GOMAXPROC，在目前这个go版本(1.2 rc2)下，不设置GOMAXPROC goroutine不会并发的，自然也没法设置memory reordering

此篇主要内容到此结束，以下是这两天的一些探索过程和技巧，觉得还是挺有意思的

go tool生成的汇编码和真实的汇编码是有很大差距的
---

这个结论并不奇怪，但是差异的程度还是会影响诸如lock-free的代码的使用前提

对以下代码做对比

    x = 1
    r1 = y
    
使用`go tool 6g -S xxx.go`反编译后的代码

    0246 (a.go:25) MOVQ    $1,x+0(SB)   //X=1
    0247 (a.go:26) MOVQ    y+0(SB),BX
    0248 (a.go:26) MOVQ    BX,r1+0(SB)  //r1=Y
    
而真实运行在cpu上的代码（`ndisasm -b 32 xxx`)为

    000013EB  C70425787F170001  mov dword [0x177f78],0x1     //X=1
             -000000
    000013F6  48                dec eax
    000013F7  8B1C25807F1700    mov ebx,[0x177f80]
    000013FE  48                dec eax
    000013FF  891C25687F1700    mov [0x177f68],ebx          //r1=Y
    00001406  48                dec eax
    
可以看到在访问共享内存的前后多出了`dec eax`作为margin，这个原因不明，也没有找到相应的资料

但总的来说`ndisasm`产生的汇编代码更方便于对go行为的理解

一个小技巧快速定位汇编码
---

我对intel指令集和go的编译器知之甚少，读起汇编码来颇为费劲。

快速定位源码对应的汇编码的位置，比较方便的就是修改一个数值，比如x=1改为x=2，前后生成的汇编码diff一下，就可以大概确定位置了

替换c++生成文件的指令
---

在探索过程中，我想做个对比实验来证明是否上面所说的`dec eax`引起了c++和go在memory reordering上的差异，于是就想将`dec eax`也加到c++的生成文件中，这样就可以对比效果

碰到的问题是如果我直接将`asm volatile("dec %eax")`直接加到c++源码中，生成的汇编代码不是`48`，而是`FExxxx`。翻看[Intel® 64 and IA-32 Architectures
Software Developer’s Manual](http://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf)，可知`dec`有多种形式

但是我不想研究为什么编译器会选择`FExxxx`而不是`48`，而是想尽快将c++生成的汇编代码形式做成和go一样。于是就有了下面的步骤：

1. `48`有两个字节，我也选取两个字节的op写在c++源码中，比如`asm volatile("cli")`
2. c++编译生成，然后用16进制编辑器将`cli`生成的两个字节换成`48`即可

之所以选择替换是因为怕有checksum或者内存位置的偏移，我也不知道有还是没有...

对比实验证明`dec eax`不是引起差异的原因