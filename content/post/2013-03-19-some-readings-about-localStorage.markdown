+++
draft = false
title = "读了“There is no simple solution for local storage”"
date = 2013-03-19T23:35:00Z
tags = [ "html5", "local storage"]
+++

作为一个非专职Client开发,偶然读了读关于localStorage的[这篇有趣的文字](http://www.36ria.com/6075),非常有意思,引文也很值得一读。

作者的思考方向很全面。摘取其中重要的部分：

1. (性能) localStorage是会阻止渲染(同步),会写I/O

2. (浏览器行为) localStorage会被浏览器预载入,会被永久存储,浏览器支持良好

3. (开发接口) 接口简单。缺少getSize这样的接口

4. (用户接口) 用户授权简单

解决localStorage问题的方案,可能是升级或者寻找替代品,衡量的方向也是上面几点。

值得一读的引文：

* [这篇引文](http://htmlui.com/blog/2011-08-23-5-obscure-facts-about-html5-localstorage.html) 描述了LocalStorage的几个限制。值得注意的是http和https的localStorage不能互通。

* [Saving images and files in localStorage](https://hacks.mozilla.org/2012/02/saving-images-and-files-in-localstorage/)