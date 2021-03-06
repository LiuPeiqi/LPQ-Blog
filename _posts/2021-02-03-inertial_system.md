---
layout: post
title: "射击MMO手游里的惯性参考系"
data: 2021-02-03
tags: GamePlay Unity Physics InertialSystem
excerpt_separator: <!--more-->
---

本文主要讨论在射击游戏里实现一个具有惯性参考系的位置、射击、技能、特效和IK功能的同步系统

<!--more-->

## 需求

我们要在大地图里做一些可移动的平板、电梯、火车，多个玩家和怪物可以在这些平台上自由移动、战斗、射击战斗以及上下平台。

### 背景

项目是mmo类的枪械射击手游，使用状态同步，原生Unity物理引擎，位置和方向数据使用定点数，但没有保证完全恢复。

## 一些朴素的想法

### 纯物理引擎托管

使用原生物理引擎，刚体加物理材质的动静摩檫力。落到平板上的单位被物理引擎带着走。一般的纯客户端本地demo这么做可以在极小的工作量下达到非常好的效果，但是对于同步其他玩家或者多端同步怪物表现则有非常大的困难。另一方面，单纯的使用物理引擎，不容易实现一些状态、技能、子弹的位移和业务逻辑。
比如根据配置需要在板上切换是相对于载具空间还是相对于大世界空间的跳跃逻辑。

* 在惯性参考系里竖直跳跃是落在相对于惯性参考系的原地还是落在相对于世界的起跳点
    * 在行进的火车车厢里竖直跳跃，要落到原地
    * 在行进的火车车顶竖直跳跃，不会落到原地

如果不干预物理引擎，那么应用场景很有限；如果要处理这些细节，那么就要写毛毛多特例分支来单独搞，甚至还搞不定。

### 使用Hierarchy挂接

直接把在平板上的单位挂接到平板上，利用Unity的Hierarchy的父子关系实现相对位移等运动逻辑。这么做的好处是引擎帮忙计算相对复杂的Transform相关数据，快速实现相对运动，也能相对灵活的切换不同参考系`trasform.SetParent(inertial_system)`。

但是这么做同样存在一些相对棘手的问题(以下问题同样适用于装备、特效、乘骑等的挂接逻辑)：

1. 同步的逻辑严重依赖渲染逻辑(GameObject--我的认知是GameObject主要是用来做渲染逻辑，而不是主要用来做GamePlay逻辑)。
1. 父节点在Active或者Deactive时不能对子节点做Attach和Detach操作(前项目为了能Att\Detach，做了大量delay一帧的操作，留下很多隐患)
1. 显隐平板时会波及到平板上的单位(由具体业务来决定要不要显隐)
1. 平板和平板上的单位先后进出视野时不好处理挂接和位置关系(额外要求服务器处理协议发送顺序与视野逻辑)
1. 如果通过对象池来优化单位创建与销毁，那么正确的拆解挂载也是一个不小的挑战
1. 平级的多个单位的更新次序不好确定

### 构造一套通用的逻辑上的Hierarchy结构

既然不能直接用原生的，那么就造轮子。先定义一个root，然后平板是root的逻辑子节点，平板上的单位是平板的逻辑子节点。参考Unity实现，只记录local position / rotation，最后每帧把逻辑位置换算成world position再设置到Transform上。
这个方案主要的问题就是性能效率了。

## 基础分析

### 跟位置密切相关的逻辑

比起常规MMO，IK对射击游戏的逻辑影响更深。比如之前MMO里使用IK只做一个表现适配：播特定动画时把头、手、脚对应到差不多的位置和方向上。而射击游戏至少要依赖IK把枪、手、肘对应到瞄准点方向，然后才能触发技能和射线检查。技能、子弹激发时再最后把特效位置对应到各个挂点上。现在再引入惯性参考系，就又增加了位置逻辑的复杂度。

除了常规技能逻辑和效果的播放，另一个惯性参考系对射击游戏的影响是子弹的出射速度，即出射速度是按照速度叠加上参考系运动还是子弹在参考系里使用local坐标运动，或者直接什么都不做。什么都不做的方案对于子弹速度远远大于参考系速度的情况下是看不出明显问题的，只有两者速度相近时才会发现问题，比如逆着火车进行方向扔一颗出手速度差不多的手雷有可能直接糊在投掷者脸上。

另一个不容易被事先想到的例子是针对粒子特效的影响。粒子特效在制作时可以选择local和world效果。两者的差别是制作一根棍子一样的刚性效果，还是制作一个喷射的火舌或者可以随目标运动而自由飘散的烟雾。引入惯性参考系后local特效不会有任何影响，因为它本身就是局部的。但是world特效就难处理了，如果在行进的火车上摆一个跟随火车移动的火把，火焰会像被风吹了一样向后摆动。针对这个效果的建议是要在制作时就主动思考这个特效是否可以合理的应用到惯性系里（比如敞篷的火车上的world特效的火把被风吹动是合理的，在车厢里的火把要做成local的特效）。

### 特效跟随

因为在[使用Hierarchy挂接](#1.2.2)里分析的问题，所以特效主动写一个跟随系统在LateUpdate里同步位置。这么做的另一个好处是特效不用考虑是挂接到世界里的单位上还是挂在参考系里的单位上的，只要特效跟随系统工作前，其他位置逻辑都处理正确，那么它的效果就是正常的。

### 单位和功能的更新次序

确定一个相对合理的更新次序有利于解决一部分上述提到的困难，另一个就是明确管理Update和LateUpdate的执行细节，避免出现意外问题。

1. 基础核心逻辑 ...
1. 消息和网络协议逻辑(服务器位置同步)
1. default(单位位置更新)
1. 一般业务逻辑.Update
1. 惯性参考系同步.Update
1. 头顶信息跟随系统.Update(单位的不明显位置跟随显示)
1. Unity动画系统(骨骼动画)
1. IK系统.LateUpdate(骨骼姿态调整)
1. Lua主更新逻辑.LateUpdate(技能和子弹逻辑)
1. 头顶信息跟随系统.LateUpdate(单位的明显的位置跟随显示)
1. 特效跟随系统.LateUpdate

### 性能问题

正如前文分析的因为不能完全都自己构造Hierarchy，又要使用相对位置来确保同步，所以折中只记录载具和载具上的单位，并限定有限层挂载，不无限兼容下去。

```
class Entity {
    public Vector3 local_pos;
    public Quaternion local_rot;
    public Transform transform;
}

class InertialFrame {
    Entity self;
    public void SyncAllChilden();
    List<Entity> eitites;
}

class InertialSystem {
    List<InertialFrame> inertial_frames_1;
    List<InertialFrame> inertial_frames_2;

    void Update() {
        foreach(var frame in inertial_frames_1) {
            frame.SyncAllChildren();
        }
        foreach(var frame in inertial_frames_2) {
            frame.SyncAllChildren();
        }
    }
}
```

这么处理的一个假设是场景中惯性参考系里的单位并不会很多，参考系里再嵌套一个参考系的情况又更少。大部分单位和第一级参考系通过业务逻辑驱动处理在世界中的位置或记录参考系中的相对位置，等惯性参考系系统更新时多算一次参考系里所有单位的位置。

### 超大地图范围的影响

因为浮点数精度限制，当在Unity里使用超大地图范围时，模型的骨骼动画会被精度问题影响而抽搐。
而具体到什么范围内就会看到抽搐，取决于具体模型的层级关系和模型动画内容。定性的来说就是播放动画的骨骼层级越深，那么就越容易碰到精度墙。
典型的float精度范围如下：

|数值|最接近的两个浮点数的差值|
|-|-|
|1000|6.10352e-05|
|10000|0.000976562|
|100000|0.0078125|
|1000000|0.0625|

使用地块平移技术可以解决这个精度问题，但是这又给业务逻辑带来了额外的负担。各个业务在使用实际位置时要先做一次转化。
如果我们把Unity实际使用的世界位置定义为WorldPos，逻辑上使用的（服务器使用的）位置定义为GlobalPos，在参考系子空间的位置定义为LocalPos，那么他们的转化关系如下：

```
GlobalPos = WorldPos + index * BlockSize;
// or
WorldPos = GlobalPos - index * BlockSize;

WorldPos = InertialFrame.WorldPos + InertialFrame.WorldRot * LocalPos
// or
LocalPos = Inverse(InertialFrame.WorldRot) * (WorldPos - InertialFrame.WorldPos)
```

需要注意的是在处理物理检测和修改Unity里Transform时，要都使用WorldPos。

### 范围、射线与技能筛选

如果各个主要的模块与逻辑更新次序调整好的话，这块逻辑反而不用特殊处理天然就是正确的。
对于立即筛选的范围或者检测的射线，不管在不在参考系里，使用WorldPos都可以满足其筛选规则。
对于持续性技能的话，也可以变成每帧或每几帧立即检测来解决。

## 实现细节

### 创建与同步

服务器把惯性参考系等同于一般单位一样同步视野信息和初始位置信息。在惯性参考系进入世界的协议里携带所有乘客ID，单位进入世界时也携带所在惯性参考系的ID。这么做有助于异步、分步处理相互之间的挂接关系。如果单位位于参考系中，那么携带的位置信息就是相对与该参考系的本地位置（LocalPos and LocalRot）。反之单位位置为世界位置（WorldPos and WorldRot）。
主角在惯性参考系里上下线不仅要有本地位置，还要携带一个额外的世界位置，原因是一般逻辑里主角上线只有加载完地图才跟服务器拉取周围视野信息，而不拉取视野信息就不知道要加载哪一个地图地块。
同步其他单位的位置信息时都要决议当前单位是否处在参考系中。如果在参考系中，那么就要给参考系记录本地位置而不处理Transform；如果不在参考系中，那么就直接给Transform设置世界位置。
对于其他业务逻辑模块的要求是不能直接设置单位的Transform。如果必要，那么使用惯性参考系提供的位置接口。
单位的移动动画的播放速率也要变成使用本地位置变化的速度以匹配相对于参考下的正确表现。

### 切换参考系

前面讨论的都是单位在参考系不变化的情况，而真实复杂的情况是角色控制移动或跳跃到静止或运动的参考系中，或反之从参考系中出来，或从一个参考系运到到一个参考系中。
切换参考系主要遇到的难点是位置和运动信息的连续性。
比如单位从参考系A跳入参考系B中，遇到的问题有：

1. 参考系A先于参考系B完成位置更新，单位脱离参
考系A完成位置转化，再进入参考系B后又会被计算一次移动。
1. 参考系B先于参考系A完成位置更新，单位脱离参考系A不进行位置转化，进入参考系B后位置错误。
1. 在参考系切换时，强行捋顺参考系的更新次序在逻辑上难度非常大。(如果使用Unity的Hierarchy来做相对位置就更难指定各个单位间更新次序)

要保证切换参考系，单位不会发生瞬间位置拉扯的问题，最主要的一点就是利用了[单位和功能的更新次序](#1.2.3)和[性能问题](#1.2.4)里假定的约束条件：

1. 世界里的参考系(第一级)的位置更新都先于所有在(第一级)参考系里的单位位置更新；
1. 第二级参考系位置更新都先于第二级参考系里单位位置更新。
1. 第二级参考系位置更新也要先于第一级参考系里的普通单位。

满足上述约束后，至少单位在运动时，各个参考系的位置都是确定的了。在切换发生时，还要把单位移动逻辑里记录的所有位置信息等价同步转化成新参考系里的位置信息。

```
function SwitchInertialFrame(local_pos, frame_1, frame_2)
    world_pos = frame_1.world_pos + frame_1.world_rot * local_pos
    local_pos = Inverse(frame_2.world_rot) * (world_pos - frame_2.world_pos)
    return local_pos
end
```

旋转也同样要转化。

### 瞄准与IK

射击游戏里同步单位的方向略微复杂：单位移动方向、单位面向、单位的枪械的朝向。在开始的设计里，移动和面向是分两条协议同步的，后面通过仔细分析发现，如果发生分包，两个协议间隔一些时间再收到，那么同步的面向就会发生错位。整理成一条的同步协议里至少要包含当前位置、移动方向、单位瞄准目标点、单位是否启用持枪IK。
当前位置和移动方向这俩个没什么问题，需要讨论的是单位瞄准目标点的设计。开始的设计是同步的单位的面向，但是分析之后发现就算把单位面向调整好，持枪的枪口方向仍然存在细节上的不正确。单位持枪其实是一个直角三角形的关系：角色的中轴线是直角点，角色面向是一条直角边，那么枪口方向就与三角形的斜边是一个方向，角色面向和枪口方向交汇的点是真实瞄准的点。
换句话来说，调整持枪方向，不仅要随瞄准目标高低调整持枪的俯仰，还要随瞄准目标距离的远近调整持枪的开合。因此通过瞄准点加当前位置两个信息就能传递完整的持枪方向和面向。
讨论回惯性参考系，如果单位在参考系中时，那么同步的位置信息和瞄准目标点就要使用参考系的本地坐标了。
最后，如果单位处于惯性参考系下，那么就要每帧重新使用本地坐标、方向、距离来计算出AimIK使用的世界坐标，然后传递给IK组件。
反之如果不在参考系中，那么就在接收协议时设置一次IK WorldPos就行。
至于同步标记启用持枪IK这个则单纯是业务需求：一些瞄准行为可能不是持枪瞄准，比如投掷手雷。

### 空间判断与特效位置

在运动的参考系中放置一个明确相对位置的特效跟随运动是容易的，但是如果先接收到一个要在某世界位置下创建一个特效的消息，然后再判断这个位置在参考系中就跟随运动就困难多了。
这里通过预先制作，在参考系模型里（比如火车）先挂一个或多个Collider Trigger来表明参考系的空间范围（车厢空间有多大）。
在游戏运行时，逻辑里通过Pos In Collider的方案来确认从属关系。
这么做带来的代价是相对低效一点，但是根据前面讨论的假设，这个问题并不是主要矛盾:

1. 参考系同时进入视野的个数非常有限
1. 只有在世界中具体位置直接放置的特效才进行检查
1. 有挂接关系的特效被特效跟随系统处理了

### 子弹逻辑与碰撞反弹

射击游戏里出了持枪射击以外，另一个一个主要的元素可能就是有一个可以弹来弹去手雷了。同样，碰撞与弹射也可以朴素的想到使用Unity物理引擎来托管表现。但是这里因为同上文类似的原因以及处理复杂的穿透和碰撞逻辑，没有直接使用物理的碰撞OnCollide来做，而是使用射线检查来主动计算碰撞反射角和动能损失。

在惯性参考系中发射子弹(手雷也是子弹的一种，只是速度慢)一般来说有三种情况：

1. 像角色单位一样直接以从属关系使用子弹的配置速度和加速度计算本地坐标。
1. 在子弹发射开始的时候直接把惯性系的速度折算进子弹的初速度里。
1. 单独记录参考系速度，每帧计算完子弹路径再叠加单独的参考位移。

第一种情况相对来说局限大一点：如果像单位一样直接计算本地坐标，那么子弹可能频繁进出多个惯性参考系空间。子弹进入空间就立刻跟随参考系运动则违反直觉(路径轨迹立刻被扭曲)，如果不跟随运动那么每帧有多次无效的位置转化计算，不仅时性能上划不来，而且还在设计编写时变得复杂。

第二种情况是最简单的实现方式，如果子弹发射时就在参考系里就把参考系的速度折算到子弹初速度里，其他时候都按照正常逻辑不用管，反之更不用特殊处理。如果时手雷，那就随着碰撞计算，当动能都损失完以后检查最后一次碰撞是不是在参考系上，如果时在参考系上，那么就把手雷从属于参考系就结束了。简单有效。

但是，实际上采用了第三种实现形式。因为它可以现实一个我认为非常好的效果：手雷在切换参考系时，不立刻完全继承参考系速度而是跟随弹性系数逐渐加速到目标参考速度。这样看起来运动相对柔和一些。计算方法也不复杂：

```
// some bullet velocity and path logic

if(inertial_velocitys.TryGetValue(bullet.id, out var inertial_velocity)) {
    bullet.position += (inertial_velocity * dt);
}

// bullet elastic logic

if(InertialSystem.IsInertialFrame(collide_id, out var frame)) {
    if(!inertial_velocitys.TryGetValue(bullet.id, out var v)) {
        v = Vector3.zero;
    }
    inertial_velocitys[bullet.id] = (frame.velocity - v) * (1 - bullet.factor) + v;
} else if(inertial_velocitys.TryGetValue(bullet.id, out var v)) {
    inertial_velocitys[bullet.id] = v * (1 - bullet.factor);
}

```

除了上述的好处以外，这么做还能带来另一个好处是在竖直运动的参考系中（比如电梯），可以很好的表现失重（重力加速度突然变小）和超重（重力加速度突然变大）的情况：参考系的加速减速运动不影响空中的子弹（手雷）。

## 仍然没有解决的问题

1. 参考系在变加速过程中不规则的改变Collider位置，会导致一些Collider在空间位置上相交，从而使物理检测失效。(手雷在变加速剧烈的电梯里会漏到电梯井里)
1. 主角还是使用物理和刚体来实现移动和惯性参考系交互的，这与其他单位同步的方式不同而产生表现差别。
1. World模式的粒子特效没有好的办法或表现随参考系移动。
1. 主角在被火车电梯等参考系撞开时，同步单位无法表现。
1. 没有实现可配置的脱离参考系的时机（起跳离开参考系和落地以后才切换参考系）。

## 结

开发一个运动的惯性参考系，并在其中实现完全的战斗体验是一个庞大的系统工程，实际工作中除了上面列举的问题以外还有毛毛多的细节、特殊处理分支和各种各样的Bug，要想表现完整还是道阻且长T_T。
