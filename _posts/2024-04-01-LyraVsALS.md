---
layout: post
title: "Lyra Vs. ALS"
data: 2024-04-01
tags: UE Animation
excerpt_separator: <!--more-->
---

ALS是UE4及之前版本流传极广的一款动画设计方案和模板，其设计优秀到被几乎除Epic外大部分重度射击、动作游戏项目引用。
Lyra是UE5新推出的TPS射击游戏小样，其中使用的动画设计方案不仅全方位使用了新引擎的动画技术细节，更是在运行性能和设计解耦方面有着非常出色的指导。
本文主要分析和对比一下两者之间的差异。

<!--more-->

## ALS的持械设计——叠加动画与混合（Ovelay）

ALS的重点是如何使用最少的基础移动动作来混合出多种多样风格化的持械动作。
这个侧重点带来的优点有：
1. 需要的动作量少，内存占用小，动作美术工作少。一套基础移动动作加n个持械姿势序列，以及必要的持械优化动作。
2. 不同持械动作切换流畅。同一个蓝图内切换不同持械状态姿势，可以针对性设计设置多样化的过渡时间和表现。
3. 上下半身分离的叠加设计方式更方便做出符合基础移动的运动倾斜和呼吸节律。

同样这个侧重点带来的缺点有：
1. 运行时开销巨大。主线程方面Update逻辑繁重，工作线程上动作混合和动态叠加节点量大，计算开销大。
2. 动作姿态上同质化严重，持械风格差异小。因为ALS只使用了一套基础的移动动作，其他持械表现都是通过动态叠加表达的，所以各个持械移动风格必然相似。尽管为了表达不同枪械的厚重，ALS设计了角色盆骨偏移，但它的表现力上限很低。
3. 上一条也产生了新的问题：角色盆骨偏移后，基础移动动作的腿脚不能精准表达原动画设计的幅度和位置。ALS通过脚本IK的机制来“掩盖”这个问题，但这样做仍然不能达到优秀的表现。
4. 随着角色持械复杂度的提升，叠加层的状态切换数量也线性增加，后续的开发维护和复用性不断降低。
5. ALS原作者对UE动画技术应用的炉火纯青，但是普通项目里的动作美术很难理解ALS中抽象的姿势混合和曲线如何实现具体的表现，这带来了项目内比较大的制作成本。（虽然我也赞同人菜就多学的观点）

## Lyra的动作设计——通过链接新的动画层来动态替换动画资源

Lyra的重点是如何设计运行效率高，开发阶段高度解耦的动作方案，同时可以兼顾精细的动作表现。
这个侧重点带来的优点：
1. 非常高的并行化和高效的运行效率。新的引擎有更强大的工具，因而在底层思路上就有更开阔的方向可以选择。
2. 极致的资源解耦。主动画蓝图里没有具体的动画资源，所有涉及到最终的表现都来源于动态链接的新动画层。
3. 极致的解耦意味着可以多人共同开发。
4. 灵活的动画层具备更丰富的动作细节表现可以通过换动画层来实现不同持械状态的风格化呈现。
5. 可以使用最传统的美术动作设计和开发模式，制作方案可繁可简。

Lyra的缺点：
1. 动画实例多，如果不加以控制对动画更新逻辑和动画事件的设计，则会拖慢运行效率。
2. 抽象程度高，如果对整体动画没有概览性认知，那么就很难理解具体的局部。
3. 依赖的动画资源多，美术制作量大，程序内存消耗多。

## 强强联合

ALS和Lyra都是两套成功的动画方案，但是它俩又不能逐条逐项的对比优劣，因为它们各自的侧重点和想解决的方向不同，关公不好战秦琼。那么最容易想到的就是能不能把它俩结合起来，把每个方案的优点都拿到手。既要极致性能和解耦又要少的动画资源和使用少量的内存空间。
如果不加思考的糅合两个方案，比如在ALS的基础上直接把叠加层或者基础移动给换成可以连接的动画层，这种做法不说能继承多少优点，但至少把每种方案的缺点都继承了：
1. ALS的设计方案和混合方案就决定了它需要主线程计算的压力特别大，就算用UE5新的节点重构ALS，那也是隔靴搔痒。在ALS的基础上再引入多个动态链接的动画层则会更加重它的能耗。
2. ALS的叠加层动画本身是非常小的，如果单纯的把这块作为动态链接的动画层来实现，那么得到的除了能安慰自己可以“解耦”持械状态以外，再没有任何运行内存上和开发上的增益。

基于以上约束条件，不如把ALS的核心思想拿来，在Lyra的方案中应用，听起来这似乎是一筐萝卜和萝卜一筐的差异，但事实上这是主次之辩。我们如果只使用ALS里的思想混合叠加出各个持械状态的基础移动动作，而不引入其它ALS的逻辑，来追求更少的资源量“生成”不同持械下的风格化动作，再嵌入到Lyra中，那么就能获取到解耦和资源量少的优势。当然，它依然比原生的方案增加了一些工作线程上的动画混合开销，好在，因为解耦所以后面还可以替换更合适的基础动作。

总的来说，各种方案都有优缺点，在参考学习时还是要先学习思路为主，不能光参考形式。