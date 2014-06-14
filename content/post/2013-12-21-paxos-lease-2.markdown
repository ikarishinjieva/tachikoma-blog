+++
draft = false
title = "对于PaxosLease的个人理解 2"
date = 2013-12-19T20:19:00Z
tags = [ "paxos lease" ]
+++

在阅读之前，请确定已浏览过[第一篇](http://ikarishinjieva.github.io/blog/blog/2013/12/19/paxos-lease/)，并阅读过以下参考文献[1]（最好是阅读过参考文献[2]）

参考文献
---

[1][【译】PaxosLease：实现租约的无盘Paxos算法](http://dsdoc.net/paxoslease/index.html)

[2] [Keyspace源码](https://github.com/scalien/keyspace/tree/master/src/Framework/PaxosLease)

---

本篇将讨论以下一些实现PaxosLease中的问题和解决：

1. 2PC 两阶段的超时设置
2. 续租困境及解决
3. Proposer对HighestPromisedProposeId的学习
4. 放弃租约

---

假设读者已经从参考文献[1]中熟悉了PaxosLease算法，在所有讨论之前，我们还是先简述一下整个PaxosLease算法，目的来统一一些术语。其中有一些空白，类似于**{1}**，后面的讨论中会将这些空白逐一填满：

**1** Proposer A 想要获得租约，生成一个新的ProposeId，组装成一个Prepare Request，并广播给所有Accepter

**2** Accepter B收到来自Proposer A的PrepareRequest，检查PrepareRequest中的ProposeId<br/>
若低于Accepter B的HighestPromisedProposeId，则忽略这一PrepareRequest，**{5}**<br/>
否则
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;将HighestPromisedProposeId置为PrepareRequest中的ProposeId
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; **{1}**
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;且向Proposer A反馈Prepare Response，Response中带有Accepter B的AcceptedProposeId（可能为空）<br/>

**3** Proposer A收到Accepter B的Prepare Response。<br/>若多数派Accepter返回的PrepareRequest中的AcceptedProposeId都为空，**{2}**，则表示多数派Accepter都可以接受Proposer A的Propose，进入Propose 阶段：
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Proposer A启动租约定时器β。定时器β超时时，重新启动Prepare阶段
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Proposer A向多数派广播ProposeRequest<br/>

**4** **{6}**

**5** Accepter B收到来自Proposer A的ProposeRequest，（再次）检查ProposeRequest中的ProposeId
<br/>若低于Accepter B的HighestPromisedProposeId，则忽略这一ProposeRequest
<br/>否则：<br/>将HighestPromisedProposeId置为ProposeRequest中的ProposeId
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;且将AcceptedProposeId置为ProposeRequest中的ProposeId
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;且启动定时器γ。定时器γ超时时，将AcceptedProposeId置为0
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;且向Proposer A反馈ProposeResponse<br/>

**6** Proposer A收到Accepter B的ProposeResponse。若Proposer A已收到多数派的ProposeReponse，则Proposer A:
<br/>可以认为自己持有租约，租约到期的时间为定时器β的超时时间，租约到期时需要清理
<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**{4}**
<br/>**{3}**<br/>

这一部分讨论2PC两阶段的超时设置
---

PaxosLease的过程引自参考[1]中，可以看到Prepare阶段没有计时器，而在Propose阶段，Proposer和Accepter分别启动定时器β和定时器γ，来表示“Propose阶段在当前节点超时，需要重新启动投票”，或者“租约在当前节点过期，当前节点可以参与新一轮投票”

可以看到这个结论与[上一篇](http://ikarishinjieva.github.io/blog/blog/2013/12/19/paxos-lease/)的描述不符，下面来解释原因

在这种设计下，若Prepare阶段有请求丢失，导致Proposer没法获得多数派的反馈，则Prepare阶段会僵死在那里

参考[1]中使用这种设计的原因是参考[1]中仅讨论了一次投票的情景，并不包括如何长期维护投票秩序。作为一个介绍性的文章，这种情景限定有助于读者理解

而实际应用中，我们必须要解决Prepare阶段的僵死情况，即在Prepare阶段也加入定时器（Keyspace中也是这样做的）：<br/>
**{1}** = "并启动定时器α，时长小于租约时长。α超时时，重新启动Prepare阶段。在节点进入Propose阶段时，取消α计时"

续租困境及解决
---

在实际应用中，希望长时间维持一个节点master的身份，而不希望master在集群里换来换去，那么当前持有租约的节点就希望能成功续租

先介绍续租的实现，参考[1]中提到“如果多数派响应了空的提案或是 *已存在提案* （即这个提案中的该请求者的租约还没有过期），它可以再次提议自己为租约的持有者”，相应的我们在过程中做出修改：<br/>
**{2}** = "或PrepareRequest中的AcceptedProposeId=Proposer A的leaseProposeId"<br/>
**{3}** = "置leaseProposeId为当前的proposeId"<br/>
**{4}** = "置leaseProposeId为0"<br/>

续租实现后，测试过程中，就会发现以下续租困境：

1. Proposer A获得租约，proposeId=1（此处我们为了方便，简化ProposeId的结构为提交次数），等待一段时间t后开始续租
2. Proposer B在t的过程中，不断尝试想获取续约，但始终得不到多数派的批准，这个过程中Proposer B发出提案的proposeId会飙升，比如说proposeId=10
3. Accepter们在Proposer B的不断尝试中，Prepare阶段HighestPromisedProposeId也跟着飙升，比如说HighestPromisedProposeId=10
4. Proposer A开始续租，proposeId=2，续租失败

解决续租困境有几种方式：

1. Accepter在定时器γ超时前，不接受新的PrepareRequest
2. Proposer续租时，将Request的ProposeId增加较大的值

我们随机选择第二种方式，那么在时间t（t<租约时长）的过程中，Proposer B能发出的Prepare Request数量，即B的ProposeId增长量Δ一定满足：Δ < ceil(租约时长/定时器α时长)。即，续租时，Proposer A的proposeId += ceil(租约时长/定时器α时长)即可。

额外一提，Keyspace中续租的时间（在获得租约后1s就开始续租）远小于Prepare/Propose阶段的超时时间，不会触发这个困境

Proposer对HighestPromisedProposeId的学习
---

解决了续租困境后，我们再设定一种困境：

1. Proposer A 持有租约，并一直续租，导致ProposeId变得很大，比如ProposeId = 10000
2. Accepter们的HighestPromisedProposeId也变得很大，比如HighestPromisedProposeId = 10000
3. 此时Proposer A离线
4. Proposer B 闪亮登场（比如在集群中补充了一台server），欲接手，发出PrepareRequest，ProposeId = 0
5. Proposer B 想要持有租约，至少要经过近10000次重试，才能将ProposeId增大到Accepter可接受的大小

这个困境的关键是在Proposer知晓的ProposeId太过落后于集群内最新的ProposeId，导致Proposer无法短时间内获得租约，而是需要长时间的重试

有两种解决方案可供参考：

1. Keyspace用的是这种方法：认为一个节点由Proposer和Accepter构成，即同一个节点Proposer和Accepter可以共享HighestPromisedProposeId。<br/>这样在上述情况下，只要集群里有任何一个Request被发给Accepter B，那么Proposer B 也可以学习到集群最新的ProposeId
2. 另一种方案是加入PrepareReject消息，在消息中Accpeter加入HighestPromisedProposeId供Promised学习，即<br/>
**{5}** = 向Proposer A反馈Prepare Reject，其中带有HighestPromisedProposeId<br/>
**{6}** = 若Proposer A收到Accepter B的Prepare Reject，则学习其中的HighestPromisedProposeId

第二种方案还需考虑网络延迟的情况，即Prepare Reject被长期延迟的情况。不过这种延迟并不会带来影响，因为

1. Proposer较晚学习到HighestPromisedProposeId，不会发生错误，只会延迟产生正确的投票结果
2. Prepare Reject的处理过程中，Proposer也会判断此消息是否是当前Request产生的Response。若Prepare Reject延迟较长，Proposer会发起新一轮的Prepare Request，收到旧的Prepare Reject则会抛弃此消息。

放弃租约
---

实际应用中，会碰到这种情况：持有租约的服务器同时肩负着其他资源的“敏感角色”，比如数据库集群中的主服务器。此时若此server挂掉，则需要等待租约过期，重新投票产生新的租约持有者，然后再由新的租约持有者裁决出新的数据库主服务器，并进行数据保护迁移。这个过程由于集群租约持有者和数据库主服务器这两种角色同时消失，会带来较大的影响。

为解决以上情况，就希望若两种角色重叠在一台server上，此时server能在**运行稳定时**放弃租约，做法有两种：

1. 如参考[1]中提到：“请求者可以发送一个特定释放消息给接受者，消息中包含了它要释放租给的投票编号。在发送释放消息之前，请求者把内部状态从“我持有租约”切换到“我没有持有租约”。”。<br/><br/>
考虑“释放消息”被长期延迟的情况，最坏的情况是没有Accepter及时收到消息，跟正常租约超时一样，需要等到多数派Accepter的定时器γ都超时，才能选出新的master。看来不会对正确性带来较大影响，只是不能及时释放租约。

2. 懒惰一点，就等到租约超时。为了不让当前Proposer再成为租约持有者，将当前Proposer“冻结” 2倍租约时长，这样既可以等到当前租约超时，又可以避免参与到下一轮投票。<br/><br/>
所谓“冻结”，即停掉一切定时器，且不发出新的request

---

至此，此篇已经描述了在实现PaxosLease中碰到的一切问题和取舍，欢迎各位反馈。