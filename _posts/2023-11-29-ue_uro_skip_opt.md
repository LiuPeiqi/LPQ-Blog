---
layout: post
title: "提升URO优化时的动画表现"
data: 2023-11-29
tags: UE Animation URO
excerpt_separator: <!--more-->
---
URO是一个常用的减少动画开销的优化方法，但是它会降低具体的动画表现。本文提供一种主线程增加极少开销的动画表现增强方案。

<!--more-->

## URO的细节

### 如何设置URO
URO全称`Update Rate Optimizations`，是引擎根据当前模型的屏占比来适当跳过动画解算帧的技术方案。它在`SkinnedMeshComponent`组件上`Optimization`分组中，当设置为`True`后`SkinnedMeshComponent`可以通过全局函数`AnimUpdateRateTick`、`AnimUpdateRateSetParams`获取当前动画需要跳过的帧数。值得一提的是`AlwaysTickPose`等更新参数是`URO`的前置控制，而不是反过来。

### 档位影响
`FAnimUpdateRateParameters`类型`AActor::UpdateRateParameters::bShouldUseLodMap`字段可以设置跳帧依据是Lod级别还是屏幕高的平方，默认是`False`，但是也没有开放对外设置，即默认使用屏幕高的平方分级。`FSkeletalMeshObject::UpdateMinDesiredLODLevel`函数中`ComputeBoundsScreenRediusSquared`计算得到的具体参数。

`AActor::UpdateRateParameters::BaseVisibleDistanceFactorThesholds`里设置具体大于多高后选择当前跳应该跳几帧（参数为数组，`Index+1`为`DesiredEvaluationRate`）。

### 执行细节
具体到每次`USkinnedMeshComponent::TickPose`会更新具体的`UpdateCounter`和`EvaluateCounter`等变量来确定当前帧是否要执行动画更新。

因为很多人第一次在了解到`URO`跳帧这个概念时会觉得被跳的过程没有动画更新，所以最后会觉得表现会有卡顿。事实上UE已经用插值的方法处理了这样的卡顿。在启用`URO`后`USkeletalMeshComponent::RefreshBoneTransforms`阶段会在`USkeletalMeshComponent::PostAnimEvaluation`函数中对骨骼数组进行插值（平滑）。

因为上述插值机制的存在，所以有些时候会发现某些骨骼动画在启用跳帧后反而变得流畅了。举个例子，门的开门关门两个姿态切换时忘记或者错误的设置过渡时间为0，那么在30FPS的帧率执行下启用`URO`就可能看到门的开关过渡过程，而关闭`URO`或者在极高帧率下就看不到开关过渡表现。

*插值是当启用了跳帧后每次都执行的，而不是只有被跳帧才执行。*

### UE留下的伏笔
`USkeletalMeshComponent::TickPose`中当发现当前帧要跳过时，会调用虚函数`UAnimInstance::OnUROSkipTickAnimation`。`USkeletalMeshComponent::PostAnimEvaluation`中在对骨骼插值前会调用虚函数`UAnimInstance::OnUROPreInterpolation_AnyThread`。

从函数后缀可以看出，`OnUROSkipTickAnimation`是主线程执行，`OnUROPreInterpolation_AnyThread`可能在其他线程执行。

## URO降低了动画表现
因为跳帧，所以动画细节减少也是必然的。这个时候目标在屏幕占比很低，因而好像也没有什么问题。但是在一些情况下，这个问题又影响较大。

### 旋转
`TPS`/`FPS`类别下游戏大部分敌人或者队友都是在举枪瞄准目标的。如果动画中又设计了上下半身分离，下半身转身通过相关动画来控制，上半身通过旋转（`AnimNode-ModifyBone`）腰身（`Spine01-Spine02-Spine03`）面对目标，那么这时候跳帧就会让角色表现出旋转卡顿或者延迟。

下图角色持枪突然向右偏转很大角度又回正就是出现的旋转延迟，移动已经旋转了角色，但是角色的上半身没有及时扭腰重新瞄准对象。

![Rotate]({{ site.url }}/images/ue_uro_skip_opt/UROAim.gif)

### 蒙太奇
一些受击动画通常通过蒙太奇播放，它们的特点是相对来说短，15帧左右，而且最大动作幅度又聚集在前几帧。这个是时候跳帧就容易看不到具体的表现。

## 增加动画蓝图以增强表现
要提高因跳帧而降低了的动画表现，最简单的办法就是关掉`URO`或者减少跳帧频率。但是更激进的做法是，如果能在跳帧时执行一个简化的动画蓝图，那么不就能提供更好的解决方案么。

### 类似Post AnimBlueprint的方案
执行另一个动画蓝图，跟这个需求最接近的就是`Post AnimBlueprint`，它在常规动画蓝图执行完以后用当前动画姿态作为输入再执行一些额外的节点。这些节点通常会是一些物理节点或者`IK`节点。

最开始的设想是利用这个后处理蓝图，那能不能让常规动画蓝图走`URO`流程，然后后处理蓝图全速不跳帧的执行。

调查之后发现存在的主要困难是：
1. `USkeletalMeshComponent`中对`AnimInstance`和`PostProcessAnimIntance`调用位置都是一样的，只是在顺序上先调用执行`AnimInstance`，然后再调用执行`PostProcessAnimInstance`。如果单独改造后处理蓝图，那么对源码的修改工程量大，对原有调用逻辑和执行关系破坏较深。
1. 构造一个类似`PostProcessAnimInstance`的，专用于跳帧时执行的动画蓝图，避免对原有后处理逻辑的影响。这样其实和上面的困难差不多，还是要自己维护一套跟跟现有逻辑相差很大的动画蓝图执行逻辑。
1. 更主要的困难是新增的这个蓝图需要的动画参数通常在之前的常规蓝图里，两边需要仔细设计好访问属性，即便这样做好了也免不了要在`UpdateAnimation`阶段的类型转换和属性访问开销，这个操作一般会在主线程里。

### CopyPose/Mesh Master Slave方案
目的还是为了构造一个全速`Tick`但是执行的动画节点数量极少的动画蓝图，而包含原来动画逻辑的蓝图还是跳帧降频执行。因此再额外创建一个`MeshComponent`假设它叫`MasterMesh`，他的动作主要输入是从原动画蓝图`CopyPose`来的，不能跳过的蒙太奇要只能出现在`MesterMesh`上的动画蓝图中，否则对于叠加蒙太奇动画则会出问题（重复叠加）。

这个方案另一个直观的影响就是我们本来是要降开销的，但是这样又引入一个全速组件，又多了额外的全套动画开销，尽管它简化了，但是花在`SkeletalMeshComponent`还是少不了。

### 不跳过蒙太奇的方案
如果不考虑上文说过的转身，单纯考虑处理不跳过蒙太奇的话还是很方便的。在`SkinnedMeshComponent::ShouldTickiAnimation`中就可以加入针对特殊蒙太奇处理的内容。这样每当上述举例的受击蒙太奇播放时，忽略跳过逻辑，保证正常的受击动画表现。

它的问题是战斗中的怪物大概率常常处于受击中，动画跳帧逻辑相当于没有，开销还是会显著增加。

## 改造UE动画调用
依据UE本身存在的虚函数`UAnimInstance::OnUROSkipTickAnimation`和`UAnimInstance::OnUROPreInterpolation_AnyThread`，大胆推测UE本身曾经也面临这个问题，并像通过这两个函数来增强在跳帧时的动画表现。

### 跳帧时的动画输入
动画蓝图的输入源头一般分为两种，一种是直接的动画资源（`AnimSequence`），一种是其他动作的复制（`CopyPose/PoseSnapShot`），动画蓝图的输出是骨骼位置数组（`TArray<FTransform> BoneSpaceTransforms`），中间过程依赖的数据是曲线（`FBlendedHeapCurve AnimCurves`）和属性（`FHeapCustomAttributes CustomAttributes`）。

如果跳帧时要想省略动画资源的解算，那么最好的办法就是把上一帧的骨骼位置数组存下来。

`USkeletalMeshComponent`组件中有两个骨骼数组，`BoneSpaceTransforms`和`CachedBoneSpaceTransforms`。它俩的区别是，`BoneSpaceTransforms`是最后渲染前使用骨骼位置，`CachedBoneSpaceTransforms`是启用跳帧后，动画蓝图输出的结果，跳帧时通过插值方法输出到`BoneSpaceTransforms`。如果使用`BoneSpaceTransforms`那么还要再加入一个新函数`OnUROPostInterpolation_AnyThread`在插值后调用并修改`BoneSpaceTransforms`。如果使用`CachedBoneSpaceTransforms`，那么在`OnUROPreInterpolation_AnyThread`函数修改就行，随后的插值过程会将结果最后输入到`BoneSpaceTransforms`中的。

### 引入新的动画图表
至此，我们就可以实时对骨骼数组进行修改了，最简单的方案就是根据`BoneIndex`直接修改骨骼位置和旋转，但是这样扩展性就极为有限了，在比较明确且极限的方案可以采用，以得到极高的性能表现。

`IAnimClassInterface::GetAnimBlueprintFunctions`可以得到每个动画蓝图类定义的各个图表（`Graph`），动画蓝图的默认图表（`AnimGraph`）位于这个数组的首位，其他新增的动画层（`AnimLayer`）依次添加在随后。因此我们可以定义一个专门用于跳帧阶段执行的动画层来灵活的修改具体骨骼，而存储的当帧骨骼数组就可以作为这个动画层的输入姿势（`InputPose`）。相比于其他正常的动画层可以通过连接操作自动调用，我们特化的动画层则需要主动处理。
派生类必要的成员声明：
```CPP
class UAnimInstanceOpt : UAnimInstance{
    FName OnSkipAnimLayerName                  = TEXT("OnUROSkipAnimLayer");
    FAnimNode_Base* OnSkipLayerRootNode        = nullptr;
    FAnimNode_LinkedInputPose* OnSkipInputPose = nullptr;
}
```

新动画层和该层的输入姿势节点初始化（`Initialize`）
```CPP
void UAnimInstanceOpt::NativeInitializeAnimation(){
    auto* AnimBPClass = IAnimClassInterface::GetFromClass(GetClass());
    for(const auto& Layer : AnimBPClass->GetAnimBlueprintFunctions()){
        if(Layer.Name != OnSkipAnimLayerName){ continue; }
        auto* RootNode      = Layer->OutputPoseNodeProperty;
        OnSkipLayerRootNode = RootNode->ContainerPtrToValuePtr<FAnimNoode_Root>(this);
        auto& Proxy         = GetProxyOnGameThread<FAnimInstanceProxy>();
        Proxy.InitializeRootNode_WithRoot(OnSkipLayerRootNode);

        auto InputPoseName = FAnimNode_LinkedInputPose::DefaultInputPoseName;
        for(auto Index = 0; Index < Layer.InputPoseNames.Num(); ++Inddex){
            if(Layer.InputPoseName[Index] != InputPoseName){ continue; }
            auto* InputProperty = Layer.InputPoseNodeProperties[Index];
            OnSkipInputPose     = InputProperty->ContainerPtrToValuePtr<FAnimNode_LinkedInputPose>(this);
            break;
        }
        break;
    }
}
```

主线程执行的更新准备，复制相关属性到代理类以方便工作线程访问：
```CPP
void UAnimInstanceOpt::OnUROSkipTickAnimation(){
    PreUpdateAnimation(0.0f);
    auto& Proxy  = GetProxyOnAnyThread<FAnimInstanceProxy>();
    auto* AnimBP = Proxy.GetAnimClassInterface();
    Proxy.InitializeObjects(this);
    PropertyAccess::ProcessCopies(Proxy.GetAnimInstanceObject(),
                                  AnimBP->GetPropertyAccessLibrary(),
                                  EPropertyAccessCopyBatch::ExternalBatched);
}
```

新动画层的核心更新（`Update`）和解算（`Evaluate`）过程，以及输出结果到`CacheBoneSpaceTransforms`中：
```CPP
void UAnimInstanceOpt::OnUROPreInterpolation_AnyThread(...){
    if (bInTickAnimation){
        OriginBoneSpaceTransforms = CacheBoneSpaceTransforms；
        return;
    }
    auto& Proxy = GetProxyOnAnyThread<FAnimInstanceProxy>();
    Proxy.ForceCachedBones();
    FMemMark Mark(FMemStack::Get());
    // initialize nodes
    OnSkipLayerRootNode->Initialize_AnyThread(FAnimationInitializeContext(&Proxy));
    // update nodes
    FAnimationUdpateSharedContext SharedContext;
    FAnimationUpdateContext Context(&Proxy, Proxy.GetDeltaSeconds(), &SharedContext);
    Proxy.UdpateAnimation_WithRoot(Coontext, OnSkipLayerRootNode, OnSkipAnimLayerName);
    // fill input pose data.
    OnSkipInputPose->CachedInputPose.CopyBonesFrom(OriginBoneSpaceTransforms);
    // evaluate nodes.
    FPoseContext EvaluationContext(&Proxy);
    EvaluationContext.ResetToRefPose();
    Proxy.EvaluateAnimation_WithRoot(EvaluationContext, OnSkipLayerRootNode);
    // fill CacheBoneSpaceTransforms
    EvaluationContext.Pose.CopyBonesTo(CacheBoneSpaceTransforms);
}
```

|Anim Layer|Detail|InputPose|
|-|-|-|
|![OnSkipAnimLayer]({{ site.url }}/images/ue_uro_skip_opt/SkipAnimLayer.PNG)|![Detail]({{ site.url }}/images/ue_uro_skip_opt/SkipAnimLayerDetail.PNG)|![input]({{ site.url }}/images/ue_uro_skip_opt/SkipAnimLayerInput.PNG)|

## 补偿新动画图表引入的问题
### 如何旋转
回到最初想解决的问题：在跳帧时依然可以修改特定骨骼以减少敌人面向的抖动。新增了动画层以后直接调用原有的`ModifyBone`依然不能解决问题：
1. 最初的旋转是通过计算目标和自身的角度差值，再`AddToExisting`调整腰椎角度以面向目标。因为原始动画资源作为输入时是没有偏转的，所以再加上当前差值就是目标角度。当使用了新的动画层以后，跳帧时再执行到`ModifyBone`时，动画的输入姿势已经有上一帧加过的偏转差值了，再加新的差值就转过头了。
1. 如果直接计算`WorldSpace`下的旋转，使用`ReplaceExisting`模式，那么就不仅要记录之前一次跳帧时已经转了多少，还要记录本身动画中原骨骼本身的旋转。计算太过复杂，不好实现。

可以解决的办法有：
1. 还是使用`AddToExisting`，每帧记录当前额外旋转的角度，下一次跳帧计算时再减去记录值就能得到正确的结果。
1. 新写个动画节点，它能像IK一样直接把腰椎转向特定的世界坐标下的位置。

这里使用上述的第二个方案，原因一个是记录每次增加值的数量要跟修改的腰椎数相关，实现出来略麻烦，灵活性低。另一个是本来目的就是要减少跳帧过程的性能开销，第二个方案直接在代码里一次计算还能节省一些节点求解的开销。具体计算过程就不展开了，就是单纯IK类角度计算。

![RotateSpine]({{ site.url }}/images/ue_uro_skip_opt/RotateSpines.PNG)

|URO|FullTick|UROOpt BoneSpaceTransforms|UROOpt CachedBone|
|:-:|:-:|:-:|:-:|
|![URO]({{ site.url }}/images/ue_uro_skip_opt/UROAim.gif)|![FullTick]({{ site.url }}/images/ue_uro_skip_opt/FullTickAim.gif)|![UROOptBoneSpace]({{ site.url }}/images/ue_uro_skip_opt/UROOptBoneAim.gif)|![UROOptCachedBone]({{ site.url }}/images/ue_uro_skip_opt/UROOptCachedAim.gif)|

### 播放蒙太奇
跟普通的动画序列资源不同，蒙太奇（`Montage`）动画的播放和数据是记录在动画实例类中（`UAnimInstance`），只有具体的动画槽节点执行到是才需要从动画实例代理（`FAnimInstanceProxy`）中获取具体姿势。为了在新动画层中加入槽节点以及和常规更新过程中无缝衔接蒙太奇，需要在跳帧时主动调用蒙太奇相关更新接口：
```CPP
class UAnimInstanceOpt : UAnimInstance{
    void OnUROSkipTickAnimation(float DeltaSeconds){
        PreUpdateAnimation(0.0f);
        // initialize obj...
        UpdateMontage(DeltaSeconds);
        UpdateMontageSyncGroup();
        UpdateMontageEvaluationData();
        // copy property access..
    }
}
```

这加入蒙太奇的相关接口调用后，还有的问题：发现蒙太奇2倍速播放了。其原因是跳帧时和正常更新时都会推进蒙太奇的进度条。解决这个问题就要对正常更新动画的`DeltaSeconds`进行修正：
```CPP
void UAnimInstanceOpt::Montage_UpdateWeight(float DeltaSeconds) {
    if (!bInUROTickAnim && UROSkipElapsedTime > 0) {
        DeltaSeconds = FMath::Max(DeltaSeconds - UROSkipElapsedTime, 0.0f);
    }
    Super::Montage_UpdateWeight(DeltaSeconds);
}
void UAnimInstanceOpt::Montage_Advance(float DeltaSeconds) {
    if (!bInUROTickAnim && UROSkipElapsedTime > 0) {
        DeltaSeconds = FMath::Max(DeltaSeconds - UROSkipElapsedTime, 0.0f);
    }
    Super::Montage_Advance(DeltaSeconds);
}

```

### 叠加蒙太奇动画
上述处理完后只是能播蒙太奇动画，如果蒙太奇资源拥有一个叠加动画轨道，那么最后的动作结果还是会抽动。原因跟旋转那一节问题类似：跳帧时动画层的输入是上一帧的动作结果，叠加动画会重复增加。
像修正蒙太奇的`DeltaSeconds`一样，如果把上一帧的叠加动画减去了，那么结果就会正确。

这一次要对`FAnimInstanceProxy`修改，新增一个虚函数接口`AdjustAdditivePoses`：
```CPP
void FAnimInstanceProxy::SlotEvaluatePose(...){
    // AnimTrack->GetAnimationPose(...);
    if (AdditivePoses.Num() > 0){
        AdjustAdditivePoses(SlotNodeName, InTotalNodeWeight, AdditivePoses);
        // AccumulateAdditivePose ..
    }
}
```

再从`FAnimInstanceProxy`派生一个新子类，来完实现虚函数接口以修正叠加动画姿势：
```CPP
class FAzureAnimInstanceOptProxy: public FAnimInstanceProxy {
    void AdjustAdditivePoses(const FName& SlotNodeName, float NodeWeight,
                             TArray<FSlotEvaluationPose>& AdditivePoses){
        // assumption AdditivePoses.Num() == 1
        if(bInUROTick){
            FSlotEvaluationPose NewPose(Last.Weight, Last.AdditiveType);
            NewPose.Pose.SetBoneContainer(&AdditivePoses[0].Pose.GetBoneContainer());
            NewPose.Pose.CopyBonesFrom(Last.Pose);
            AdditivePoses.Add(MoveTemp(NewPose));
            return;
        }
        Last.Weight       = NodeWeight;
        Last.AdditiveType = AdditivePoses[0].AdditiveType;
        Last.Pose.Reset(AdditivePoses[0].Pose.GetNumBones());
        for(const auto& Index : AdditivePoses[0].Pose.ForEachBoneIndex()){
            const auto& Bone = AdditivePoses[0].Pose[Index];
            Last.Pose.Emplace(Bone.GetRotation().Inverse(), Bone.GetTranslation() * -1,
                              Bone.GetScale() * -1);
        }
    }
}
```

|URO|FullTick|UROOpt|
|:-:|:-:|:-:|
|![URO]({{ site.url }}/images/ue_uro_skip_opt/URO_clip_2.gif)|![FullTick]({{ site.url }}/images/ue_uro_skip_opt/FullTick_clip_2.gif)|![UROOpt]({{ site.url }}/images/ue_uro_skip_opt/UROOpt_clip_2.gif)|

## 具体性能开销
新引入的动画图层又带来了额外的求解过程，所以性能上是介于不跳帧和常规跳帧之间。

以下系列图中`GameThread`代表动画主线程更新耗时，`Total`代表动画在工作线程解算耗时，尾缀表示跳帧程度，图中表达了跳1、2、4、5帧的情况。


没有蒙太奇的情况：

![Normal]({{ site.url }}/images/ue_uro_skip_opt/profiling_normal.PNG)

有30%时间播放单个蒙太奇的情况：

![30%montage]({{ site.url }}/images/ue_uro_skip_opt/profiling_30montage.PNG)

**以上数据不是定量评定的，只能当作定性分析，30%蒙太奇的消耗是推算出来的，方法是$0.7 * NormalFrame + 0.3 * MontageFrame$.**

具体的火焰图如下：
带蒙太奇的常规动画更新

![Update With Montage]({{ site.url }}/images/ue_uro_skip_opt/npc_uro_montage_update.PNG)

跳帧时的动画更新

![URO Update on Skip]({{ site.url }}/images/ue_uro_skip_opt/npc_skip_update.PNG)

使用新动画层时的动画更新

![UROOpt Update on Skip]({{ site.url }}/images/ue_uro_skip_opt/npc_uroopt_montage_update.PNG)

带蒙太奇的常规动画解算

![Evaluate With Montage]({{ site.url }}/images/ue_uro_skip_opt/npc_uro_montage_evaluate.PNG)

跳帧时的动画解算

![URO Evaluate on Skip]({{ site.url }}/images/ue_uro_skip_opt/npc_skip_evaluate.PNG)

使用新动画层时的动画解算

![UROOpt Evaluate on Skip]({{ site.url }}/images/ue_uro_skip_opt/npc_uroopt_evalute.PNG)

![UROOpt Evaluate on Skip]({{ site.url }}/images/ue_uro_skip_opt/npc_uroopt_montage_evaluate.PNG)

## 没有解决的问题
### 新增蓝图的曲线和属性
完成上述所有改造后似乎很完美，但是实际仍然没有处理在跳帧时的中间变量：资源中的曲线（`Curves`）和属性（`CustomAttributes`）。
没有处理的原因：
1. 跳帧时的动作输入本来就是上一帧的结果，没有新的来源于资源中的具体数值。
1. 如果蒙太奇叠加动画携带曲线，那么还是会出现错误。原因是在`AdjustAdditivePoses`中对曲线和属性进行修正太过繁琐而判断适用范围小。

### 步伐平缓
假设一种情况，虽然在通常下很难见到这么极端的情况：角色跑动步幅频率是一秒5步，动画跳5帧更新（`30FPS/s`）。这个条件下动画会因采样失真而完全看不到目标角色的跑步动作。

设想过一种解决方案是跳帧数不按照固定的帧数，而是动态的从资源中获得。比如在角色的移动动作中加入一个指导跳帧数的曲线，其数值是当前帧可以安全跳过的帧数，当每次动画更新时就把这个数值记录到`URO Param`的`SkipCounter`上。那什么位置是不能安全跳过的帧呢，比如说脚在空中最高最低处，比如某个动作幅度最大处等等。

![key_steps]({{ site.url }}/images/ue_uro_skip_opt/steps.PNG)

对于多个动作混合的话，一方面需要`SyncMark`同步相位；另一方面步幅最好用`SpeedWarping`方式处理，单纯的`BlendSpace`或者`MutiBlend`得到的混合曲线不合适。

