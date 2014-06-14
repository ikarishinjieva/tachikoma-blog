+++
draft = false
title = "Javascript quiz from Nicolas C.Zakas"
date = 2013-02-03T23:36:00Z
tags = [ "javascript"]
+++

Nicolas C.Zakas写了五个js语言用例的分析。举一例：

```
function b(x, y, a) {
    arguments[2] = 10;
    alert(a);
}
b(1, 2, 3);
```

结果是10。出乎意料。