+++
draft = false
title = "Q源码里uncurry函数分析"
date = 2013-02-04T23:04:00Z
tags = [ "Q", "javascript", "uncurry"]
+++

[Q](http://documentup.com/kriskowal/q/)里关于uncurry的代码

```
// Attempt to make generics safe in the face of downstream
// modifications.
// There is no situation where this is necessary.
// If you need a security guarantee, these primordials need to be
// deeply frozen anyway, and if you don’t need a security guarantee,
// this is just plain paranoid.
// However, this does have the nice side-effect of reducing the size
// of the code by reducing x.call() to merely x(), eliminating many
// hard-to-minify characters.
// See Mark Miller’s explanation of what this does.
// http://wiki.ecmascript.org/doku.php?id=conventions:safe_meta_programming
var uncurryThis;
// I have kept both variations because the first is theoretically
// faster, if bind is available.
if (Function.prototype.bind) {
    var Function_bind = Function.prototype.bind;
    uncurryThis = Function_bind.bind(Function_bind.call);
} else {
    uncurryThis = function (f) {
        return function () {
            return f.call.apply(f, arguments);
        };
    };
}
var array_slice = uncurryThis(Array.prototype.slice);
```

Uncurry/反柯西化的定义可参见[wiki](http://en.wikipedia.org/wiki/Uncurry)，不是吾等凡人可以理解的。

从结果看，假设想调用[].slice，如果用uncurryThis(Array.prototype.slice)([])这种形式，可以防止其后[].slice被重写或者[].slice.call被重写。保证当前代码被保护起来，不受之后代码函数重写的影响。

对于Q里用到的这种形式，前提条件是Function.prototype.bind和Function.prototype.bind.call在之前不被重写。简单推导array_slice

```
array_slice = uncurryThis(Array.prototype.slice) 
= Function.prototype.bind.bind(Function.prototype.bind.call)(Array.prototype.slice)
= Function.prototype.bind.call.bind(Array.prototype.slice) //Function.prototype.bind.call.bind is safe
= Array.prototype.slice.call //Array.prototype.slice.call is safe
//Array.prototype.slice is also safe
```

不过，Q的注释里写的很清楚，uncurry在这里不是必要的... 写写而已...

一些参考：

[这篇文章](http://wiki.ecmascript.org/doku.php?id=conventions:safe_meta_programming) 详细介绍了safe meta programming，对uncurry做了定义和代码演示。