+++
draft = false
title = "octopress win7上遭遇invalid GBK character exception"
date = 2013-02-04T21:59:00Z
tags = [ "octopress"]
+++
解决方案：
将markdown文件保存格式设为 UTF-8 without BOM，并
在环境变量里加上 LC_ALL=zh_CN.UTF-8
