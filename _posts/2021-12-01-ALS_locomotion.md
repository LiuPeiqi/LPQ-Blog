---
layout: post
title: "UE ALS学习笔记之基础运动动画控制"
tags: UE ALS Animation
excerpt_separator: <!--more-->
---

以下作为学习ALS(Advanced Locomotion System)的笔记，相比于网上其他大佬总结的ALS教程“它是什么”，本文侧重于“尝试猜测ALS为什么这么实现，想解决什么问题”。

因为作为UE初学者，相比于蓝图，我更容易理解代码逻辑。所以本文除了基于原始[ALS插件](https://www.unrealengine.com/marketplace/zh-CN/product/advanced-locomotion-system-v1)的对比与学习以外，主要还是依据[ALS-Community](https://github.com/dyanikoglu/ALS-Community)以及其C++逻辑实现来分析的。

<!--more-->

## 学习参考

常规介绍性的内容就不啰嗦了，下面列一些学习过程中看过的文章。

- [ALS一些基础概念和分块介绍](https://www.bilibili.com/read/cv9226463)
- [ALS详细的拆解](https://zhuanlan.zhihu.com/p/159646345)
- [系列专栏里关于ALS的篇章](https://zhuanlan.zhihu.com/p/141266454)
- [UE的动画基础](https://zhuanlan.zhihu.com/p/439150072)


## ALS是如何确定走跑姿势的

### 动画依赖的变量

ALS有几个关键性参数来确定走跑或者疾跑姿势。按更新顺序如下，`C++`表示ALS-Community实现。 

Character相关：

- `Desired Gait`，`ALS_Base_CharacterBP`里接受玩家输入事件的变量，C++里在`ALSBaseCharacter.h`。
- `Allowed Gait`，`Actual Gait`，临时变量，C++`ALSBaseCharacter::UpdateCharacterMovement()`里逻辑比较明显。
    - `Allowed Gait`受当前`Stance`站蹲姿态影响。
    - `Actual Gait`受当前`Speed`和`CharacterMovementComponent`里配置的走跑速度影响。
- `Gait`，`ALS_Base_CharacterBP`里和`ALS_AnimBP`里都有的同名变量，但枚举类型不同。
    - `ALS_Base_CharacterBP`里依据上面Desired Gait和Allowed Gait得来，作为最后的状态枚举。
    - `ALS_AnimBP`里的`Gait`以下动画再提及的Gait就是特指`ALS_AnimBP`里的变量。
        - `ALS_AnimBP`里通过`Event Blueprint Update Animation` => `Update Character Info`节点赋值。
        - C++里通过Character直接给AnimInstance赋值。

Animation中混合空间相关的变量，`ALS_AnimBP`在`Event Blueprint Update Animation` => `Update Movement Values`节点里计算。C++在`ALSCharacterAnimInstance::NativeUpdateAnimation()`的`UpdateMovementValues()`计算。

- `Walk Run Blend`，C++`Grounded.WalkRunBlend`。`Gait`是走为0，其他（跑、疾跑）为1。
- `Stride Blend`，C++`Grounded.StrideBlend`。根据当前移动速度，再以当前动画曲线和配置曲线来计算当前步幅。
- `Standing Play Rate`，C++`Grounded.StandingPlayRate`。以速度和当前走跑姿势融合程度来确定动画播放速率。这个是平顺实现走跑过度的关键。

### 曲线

动画曲线`Weight_Gait`，C++里叫`W_Gait`。这个曲线是定义在基础locomotion动画资源里的，原始动画资源位于`AnimationExamples/Base/Locomotion`文件夹下各个Walk、Run、Sprint动作。

```
Walk:   Weight_Gait = 1
Run:    Weight_Gait = 2
Sprint: Weight_Gait = 3
```

除了动画曲线外，还非常依赖额外配置的动画混合曲线来计算出当前移动速度下准确的步幅。资源位于`Data/Curves/AnimationBlendCurves`，影响步幅的曲线是`StrideBlend_N_Run`等。

相比于Unity，UE动画曲线和曲线资源可以解决非常多原来看起来很困难的问题。比如之前项目就存在角色移动速度和动画融合后的速度不匹配的问题(动画虽然是线性融合的，但是动画Key出来的结果却是非线性的，因此融合参数也就难确定)。当时找了很多方向，都没解决好。而现在类比到ALS中，使用类似`StrideBlend_N_Run`的曲线修正一下融合参数就可以完美解决。

### 走跑混合——为什么要采用步幅的混合方式

ALS使用一个二维混合空间(BlendSpace2D)来实现走跑姿态混合是非常厉害的方案。比如打开`ALS_N_WalkRun_F`资源，它横轴参数是步幅，纵轴参数是走或跑，四个sample点分别为走动作、跑动作、走姿态下步幅为0的动作、跑姿态下步幅为0的动作。
使用走和跑动作来融合问题不大，但是走姿态下步幅为0的动作这个设计是非常棒的。相比于Unity的混合树(BlendTree)来说，Unity项目通常使用空闲站立、走动作、跑动作来混合出不同的速度下的动作表现。这样做不是不能用，但是当融合参数处于站走混合过程中或走跑混合时，它输出的动作大概率有问题。包括不限于走跑动作幅度差别大导致的屈腿奇怪姿势；走跑相位不一致导致的颠儿腿；站走、走跑时手臂姿势差别大导致的不自然摆臂。
ALS中，走姿态下步幅为0的动作其实就是一个站立动作，跑姿态下步幅为0的动作有点像中学跑操时预备跑的动作：屈腿站立，提手屈肘。当这个预备跑动作和跑动作再进行融合时，那它就能刚好解决上面说的走跑步幅、相位、手臂姿势有差异的问题，多了新的采样维度——步幅。
ALS主要是使用步幅来控制动画表现的移动速度的，半跑半走的速度就使用0.5步幅的跑姿态(事实上是由上面提过的混合曲线确认的数值，不是绝对的0.5)。再对比Unity项目（包括官方指导和Animancer插件，都是如此），普遍会使用0.5权重走动作和0.5权重跑动作融合。
最后，其实ALS可以不把走跑动作放到一个BlendSpace2D里的，而是单独放两个BlendSpace1D。虽然ALS在计算`WalkRunBlend`参数时只会明确输出0或1，不会输出其他中间值。但它仍然没有这么做，我猜测一是为了减少蓝图里直接编辑的资源量，二是可以方便再扩展新的混合策略。
ALS使用`Stride Blend`，`Walk Run Blend`，`Standing Play Rate`三个参数来唯一确认走跑6个方向混合动画。

总的来说，使用步幅的混合方式能在避免走跑动作混合时出现的一些细节问题的同时，还能提供更平顺自然的动作切换表现。

### 疾跑处理

还是说回Unity，以前项目在处理疾跑的时候也有两个阶段，第一阶段是直接都放在BlendTree里混合，提供了四个Sample：`Stand, Walk, Run, Sprint`，通过速度参数控制混合比例。但是这么做带来的问题是跑到疾跑的过渡表现不好看。后一阶段就拆开了疾跑，由基础动作Fade到疾跑动作。依然存在的问题是Fade过程中有可能出现因前后动作相位不一致导致的颠儿腿现象。
**为什么不把疾跑也放到走跑混合空间里做？** 
一句话解释就是疾跑动作和跑动作的差异太大了，同时混合效果不好。

ALS对疾跑处理的比较细腻，先计算了归一化的加速度`RelativeAccelerationAmount`，然后用这个值混合了疾跑动画和带加速度的疾跑动画(会俯身)。
除了使用`Gait`来切换前向移动和疾跑移动，ALS还提供了一个Mask机制。我认为这个机制也非常好。
很多动画之间是互斥的，如果同时存在就会穿帮。之前项目处理这种情况的时候多半要硬写逻辑，处理起来还很不顺手，多次修改能让后来人绝望。而这个Mask机制则是非常灵活和容易扩展的，只要在必要的动作资源上加上对应的曲线就可以了。
已经切换过的动作再经过`Mask_Spint`曲线再做一次确认，如果mask值为1，那么就不选择疾跑动作。至此角色的6个方向走跑动作就完成了所有的预处理。

我在ALS里疾跑切换中没有看到相关对于动作相位的同步控制，可能ALS也会有类似问题，也可能现阶段只是我没找到相关逻辑，后面再研究一下。

## ALS如何混合多方向移动动作的

### 为什么不是8方向混合

ALS使用一个子状态机来处理运动方向上的融合，它特殊在是6个方向（前`Move F`、后`Move B`、左前`Move LF`、左后`Move LB`、右前`Move RF`、右后`Move RB`）的融合而不是8个方向的。而理解这个设计的巧妙，还是要先说一下之前是怎么做4、8方向移动混合的：美术输出前后左右移动动作，然后根据速度方向和面向角度差计算混合参数，斜向移动动作是相邻的两个动作混合出来的。如果觉得动作不够精细，那么就再加4个45°的斜向动作。但是它仍然存在较多问题：

1. 融合出来的斜向动作姿势与美术想要的质感差距较大且无法调整。如果强行纠正只能再增加新的斜向动作作为采样点，这样带来的资源数和内存开销的激增。
1. 融合出来的斜向动作的移动速度不是线性的且不好预知的。如果基础动作也使用RootMotion来驱动角色移动，那么会对逻辑提出较大挑战；如果放任不管，那么斜向移动的角色会非常明显的黄油脚。
1. 融合参数在计算时其实是有小坑的：融合参数如果通过线性方法计算得出，那么是不准确的。需要使用主采样方向的正切方法计算。
1. **移动方向在切换时，或特定的融合角度，角色动画容易发生绊脚的问题。** 如果说前面三点还能勉强忍受的话，那么这一点美术同学是真的不能接受。

### 方向混合的参数

在研究ALS的6向混合方法时候给我最大的困扰是：它怎么向着左或者右水平移动呢？需要左前和左后来混合么？
这里先把怎么确认角色旋转方向的问题放一下以后再分析，原因是角色的面向、移动方向、瞄准方向其实是一个细节非常多的大议题。本文先重点关注一下当方向确认后，如何选用和切换角色具体方向上的移动动作。

ALS里主要通过`Movement Direction`枚举来确认基本的方向动作，它只有前后前后左右四个值，通过`UpdateGraph` => `Do While Moving` => `Update Rotation Values`中计算。相较于ALS版本复杂的线框图，C++中`UALSCharacterAnimInstance::CalculateMovementDirection()`和`UALSMathLibrary::CalculateQuadrant()`两个函数的逻辑非常清晰。方向枚举的切换里面有个动态范围的细节，如果感兴趣可以单独看一下。

除了`Movement Direction`枚举以外，还要计算 **4个** (居然不是6个动作)方向上动作的融合参数`Velocity Blend`，包含四个分量：`F, B, L, R`。C++的计算逻辑在`UALSCharacterAnimInstance::UPdateMovementValues()` => `UALSCharacterAnimInstance::CalculateVelocityBlend()`。细节包括归一化和速度插值等。

接下来是解决上一小节四个问题的关键性参数：`FYaw, BYaw, LYaw, RYaw`。它们在动画蓝图里被6个方向状态赋值给曲线`YawOffset`，然后在`ALS_Base_CharacterBP` => `Update Grounded Rotation`蓝图里读取该曲线数值再作用于角色旋转。其中包含两个(`YawOffset_FB, YawOffset_LR`)配置曲线资源来计算输出数值。

1. 状态`Move F`，设置`FYaw`数值到曲线`YawOffset`。
1. 状态`Move B`，设置`BYaw`数值到曲线`YawOffset`。
1. 状态`Move LF`和`Move LB`，设置`LYaw`数值到曲线`YawOffset`。
1. 状态`Move RF`和`Move RB`，设置`RYaw`数值到曲线`YawOffset`。

这个`YawOffset`表示的意思是在当前移动动作下，再补多少角度可以匹配到垂直或水平移动方向上。举个例子，其中涉及数值只是定性的表达意思，非定量的准确数值。

1. 角色前向移动，使用前向动作，`YawOffset`为0，角色不额外旋转。
1. 角色右向移动（+90°），使用右前动作(运动方向是+60°)，`YawOffset`为30°，角色再额外向右旋转30度。

所以到这里先回答一下上一个小节的问题，ALS怎么解决因各个斜向运动导致的融合问题呢？
**答案是不融合动作**，跳出旧逻辑，直接使用额外的角色旋转控制，把所有斜向速度方向都纠正成相对于当前移动动作方向再做偏移的方向。随后再在蓝图中配合角色注视逻辑，把头扭到摄像机方向。这样即实现了多向运动，又避免动作融合带来的种种困难。
我认为这块逻辑有点脑筋急转弯的意思，想到了，方案很简单，没想到就很困难。

### 各个方向状态的转移

先说明的一点是6个移动状态里都是4个动作参与混合的，分别由结构体`VelocityBlend {F, B, L, R}`数值控制权重。但是它们每一个时刻最多只有两个动作参与融合，细节其实在曲线资源`YawOffset_FB`和`YawOffset_LR`中配置体现的。

前和后状态的切换是最直接的，只要`Movement Direction`是前或者后，就会切换到对应状态上。向左和向右切换则包含了一些有意思的细节：

1. 处于前或者后时切换左右，直接切换到最近的对应方向：前状态+左输入=>左前状态，后状态+左输入=>左后状态。
1. 左右状态互切是按照对角切换的：左前状态+右输入=>右后状态，左后状态+右输入=>右前状态。
1. 左右状态会根据上层`HipOrientation_Bias`曲线(Overlay相关动作资源携带)和`Feet_Crossing`(Base locomotion相关动作资源携带)自动切换左前左后(右前右后)。
    1. `HipOrientation_Bias`曲线表现当前overlay姿态优先使用哪个方向。0表示默认，1表示优先使用右前或者左后动作(大部分双手瞄准动作)，-1表示优先使用左前或者右后动作(单手持手枪瞄准动作)。为了让动作姿态更舒展，而选用更合适的斜向动作。
    1. 对于`Feet_Crossing`曲线来说，值为1表示当前动作两腿正在交叉，不允许进行左右状态切换。0表示没有交叉，可以进行切换左右脚。**强化解决绊腿问题**。
1. 没有特殊设定(`HipOrientation_Bias`曲线)影响时，左右移动会在左后或者右后状态完整切换完自动再切换到左前或者右前状态。
    1. 表现为只要没有输入“后”操作，就尽量选用包含前向的动作。
    1. 如果是从后状态切换到左右的，那么会执行一个完整的状态过度，再切换到目标状态，以此实现更平顺的姿态切换。

### 运动倾斜

一个锦上添花的小细节，但是之前项目会单独制作一个过度动画来实现。
ALS使用角色运动的加速度信息和一个叠加(Additived)的BlendSpace2D动画资源来混合。好处是能提供更丰富，逻辑更简单的实现方式，缺点是需要额外的混合计算开销。

## 再谈ALS中曲线的应用

朴素的来说，大家一般设计动画驱动逻辑时都想做好逻辑和表现的剥离，降低逻辑与动画的耦合。但是这么会做大大降低逻辑对动画精细表现的控制能力。
而ALS则提供了一个非常好的耦合方案，让逻辑控制动画、动画控制逻辑很好的配合在一起：在各个模块里构成“*逻辑驱动状态——状态驱动动画——多处动画曲线的混合结果修改逻辑状态*”的三明治结构。
另外一个重点就是使用配置曲线来处理大量非线性数值逻辑，简化美术制作以及程序逻辑。可以看到后面还会在角色攀爬、翻跨实现里发挥更重要的作用。
当然它的缺点就是在初期非常难以理解，有大量的Magic Number、Bias、Clamp行为导致目的和语义不明确。
