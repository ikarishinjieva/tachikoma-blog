+++
draft = false
title = "栽在Go中for的变量"
date = 2013-12-26T22:13:00Z
tags = [ "go" ]
+++

我是万没料到自己栽在了go的for上，说多了都是眼泪

``` 
type testStruct struct {
     no int
}

func main() {
     a := []testStruct{testStruct{1}, testStruct{2}, testStruct{3}}
     var p *testStruct
     for _, i := range a {
          if i.no == 2 {
               // o := i
               // p = &o
               p = &i
          }
     }
     fmt.Println(p.no)
} 
```

猜猜看输出是多少？[试试看吧](http://play.golang.org/p/OzkxuYIboc)

理解起来很容易，`p`取得是`i`的地址，而**range循环变量`i`在每个循环之间都是复用同一个地址**

证明一下，[试试看？](http://play.golang.org/p/b3QFcoh35Q)

```
a := []int{1, 2, 3, 4, 5}
for _, item := range a {
     fmt.Printf("%p\n", &item)
} 
```

虽然很容易理解，也很容易掉坑，尤其for上用`:=`，那感觉就像js里连续用`var`，除了第一下剩下的都不好使...