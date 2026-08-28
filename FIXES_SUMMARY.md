# KSPlayer 代码修复总结

本次修复解决了代码审查中发现的高危问题以及长时间运行后的闪退问题。

---

## 一、高危问题修复（11项）

### 1. CircularBuffer.swift - 缓冲区覆盖问题
**文件**: `Sources/KSPlayer/MEPlayer/CircularBuffer.swift`
- **问题**: `push()` 在检查容量前就写入，缓冲区满时覆盖最旧元素
- **修复**: 先检查容量再写入，添加扩容分支
- **影响**: 防止数据丢失和潜在崩溃

### 2. AudioEnginePlayer.swift - 音频线程竞态
**文件**: `Sources/KSPlayer/MEPlayer/AudioEnginePlayer.swift`
- **问题**: `currentRender`/`currentRenderReadOffset`/`sampleSize` 在音频渲染线程与主线程间无锁访问
- **修复**: 添加 `NSLock` 保护共享状态，添加同步副本用于音频回调
- **影响**: 防止撕裂读、越界读导致崩溃

### 3. Resample.swift - swr_convert 负值回绕
**文件**: `Sources/KSPlayer/MEPlayer/Resample.swift`
- **问题**: `swr_convert` 负错误码强转 `UInt32` 回绕成巨大值
- **修复**: 检查负值并抛出错误
- **影响**: 防止越界读导致崩溃

### 4. Model.swift - toPCMBuffer 越界写
**文件**: `Sources/KSPlayer/MEPlayer/Model.swift`
- **问题**: 平面音频时 `dataSize` 被当每声道容量（实际是总字节数）
- **修复**: 根据 `isInterleaved` 正确计算每声道容量
- **影响**: 防止堆越界写导致崩溃

### 5. FFmpegDecode.swift - 关键解码错误
**文件**: `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift`
- **问题1**: `display_primaries_b_x` 复制粘贴错误（`.2.1` 而非 `.2.0`）
- **问题2**: 硬件解码路径 CVPixelBuffer 未 retain
- **问题3**: 错误时不调用 `completionHandler`
- **问题4**: 对 nil codecContext 调 `avcodec_flush_buffers`
- **修复**: 修正字段、添加 CFRetain、添加回调、添加 nil 检查
- **影响**: 修复 HDR 元数据错误、use-after-free、回调丢失

### 6. MEPlayerItem.swift - NSCondition 误用
**文件**: `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
- **问题**: `condition.wait()` 未持锁，`signal()`/`broadcast()` 也未持锁
- **修复**: 所有 condition 操作都持锁
- **影响**: 防止唤醒丢失导致永久阻塞

### 7. KSMEPlayer.swift / KSAVPlayer.swift - seek 状态机
**文件**: `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift`, `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift`
- **问题**: seek 后 `playbackState` 永远保持 `.seeking`
- **修复**: seek 完成后恢复 `playbackState` 为 `.playing`
- **影响**: 修复 seek 后播放停止的问题

### 8. MetalRender.swift - 10-bit 帧不渲染
**文件**: `Sources/KSPlayer/Metal/MetalRender.swift`
- **问题**: 10-bit 平面帧（`leftShift > 0`）从不渲染，drawable 池耗尽
- **修复**: 支持 `PixelBuffer` 非 CVPixelBuffer 类型，移除主线程阻塞
- **影响**: 修复 10-bit HDR 视频无法播放

### 9. Transforms.swift - lookAt 矩阵转置
**文件**: `Sources/KSPlayer/Metal/Transforms.swift`
- **问题**: `lookAt` 矩阵转置（眼偏移在末行而非末列）
- **修复**: 使用 `columns` 初始化器
- **影响**: 修复 VRBox 双眼无立体视差

### 10. Utility.swift - parsePlaylist 死循环
**文件**: `Sources/KSPlayer/Core/Utility.swift`
- **问题**: 非标准换行分隔的 m3u 文件导致死循环
- **修复**: 添加换行符消费逻辑
- **影响**: 修复解析挂起

### 11. FFmpegBuild/main.swift - 构建脚本错误
**文件**: `FFmpegBuild/Plugins/BuildFFmpeg/main.swift`
- **问题1**: `Libxxx.a` vs `libxxx.a` 文件名不匹配
- **问题2**: `xcrun --find --show-sdk-path` 非法调用
- **修复**: 添加小写备选、分离调用
- **影响**: 修复 FFmpeg xcframework 无法构建

---

## 二、内存泄漏修复（8项）- 解决长时间运行闪退

### 1. CVMetalTexture 内存泄漏
**文件**: `Sources/KSPlayer/Metal/MetalRender.swift`
- **问题**: 每次渲染创建的 CVMetalTexture 从未被释放
- **修复**: 在 command buffer completion handler 中调用 `CFRelease`
- **影响**: 防止 Metal 纹理缓存耗尽导致内存不足崩溃

### 2. CVMetalTextureCache 从未刷新
**文件**: `Sources/KSPlayer/Metal/MetalRender.swift`, `Sources/KSPlayer/MEPlayer/MetalPlayView.swift`
- **问题**: Texture cache 从未 flush
- **修复**: 添加 `flushTextureCache()` 方法，在 `flush()`/`invalidate()` 时调用
- **影响**: 防止纹理无法回收

### 3. VideoVTBFrame CVPixelBuffer 生命周期
**文件**: `Sources/KSPlayer/MEPlayer/Model.swift`, `Sources/KSPlayer/MEPlayer/Resample.swift`
- **问题**: 硬件解码路径的 CVPixelBuffer 引用计数管理错误
- **修复**: 获取时 `CFRetain`，deinit 时 `CFRelease`
- **影响**: 防止硬件解码帧泄漏

### 4. VideoSwscale outFrame 泄漏
**文件**: `Sources/KSPlayer/MEPlayer/Resample.swift`
- **问题**: 格式切换和 shutdown 时未释放 `outFrame`
- **修复**: 在格式变化和 `shutdown()` 中调用 `av_frame_free`
- **影响**: 防止软件解码帧泄漏

### 5. PiP 控制器静态泄漏
**文件**: `Sources/KSPlayer/AVPlayer/KSPictureInPictureController.swift`
- **问题**: `isPipPopViewController == false` 时静态引用永不清除
- **修复**: 在 `stop()` 中始终清除静态引用
- **影响**: 防止 PiP 泄漏整个播放器

### 6. 通知观察者泄漏
**文件**: `Sources/KSPlayer/Video/BrightnessVolume.swift`
- **问题**: 音量通知观察者注册但从未移除
- **修复**: 在 `deinit` 中调用 `removeObserver`
- **影响**: 防止观察者累积导致通知分发给已释放对象

### 7. tvOS Slider Timer 泄漏
**文件**: `Sources/KSPlayer/SwiftUI/Slider.swift`
- **问题**: 重复 Timer 永远不会被 invalidate
- **修复**: 添加 `deinit` 调用 `timer.invalidate()`
- **影响**: 防止定时器累积耗尽系统资源

### 8. Packet corePacket nil 安全
**文件**: `Sources/KSPlayer/MEPlayer/Model.swift`
- **问题**: `deinit` 中对 nil `corePacket` 调用 `av_packet_unref`
- **修复**: 添加 nil 检查
- **影响**: 防止异常情况下的崩溃

---

## 三、修改的文件清单（共 13 个文件）

```
Sources/KSPlayer/MEPlayer/CircularBuffer.swift
Sources/KSPlayer/MEPlayer/AudioEnginePlayer.swift
Sources/KSPlayer/MEPlayer/Resample.swift
Sources/KSPlayer/MEPlayer/Model.swift
Sources/KSPlayer/MEPlayer/FFmpegDecode.swift
Sources/KSPlayer/MEPlayer/MEPlayerItem.swift
Sources/KSPlayer/MEPlayer/KSMEPlayer.swift
Sources/KSPlayer/AVPlayer/KSAVPlayer.swift
Sources/KSPlayer/Metal/MetalRender.swift
Sources/KSPlayer/Metal/Transforms.swift
Sources/KSPlayer/Core/Utility.swift
Sources/KSPlayer/MEPlayer/MetalPlayView.swift
Sources/KSPlayer/AVPlayer/KSPictureInPictureController.swift
Sources/KSPlayer/Video/BrightnessVolume.swift
Sources/KSPlayer/SwiftUI/Slider.swift
FFmpegBuild/Plugins/BuildFFmpeg/main.swift
```

---

## 四、测试建议

### 1. 长时间播放测试
- 播放同一视频 1-2 小时，监控内存使用
- 预期：内存稳定，无明显增长

### 2. 多次 seek 测试
- 反复 seek 100 次以上
- 预期：播放器状态正常，无卡顿

### 3. 切换视频测试
- 连续切换不同视频 20 次以上
- 预期：切换流畅，内存稳定

### 4. PiP 测试
- 进入/退出 PiP 多次
- 预期：功能正常，无泄漏

### 5. 后台切换测试
- 反复进入后台/前台
- 预期：播放正常恢复，无崩溃

### 6. HDR/10-bit 视频测试
- 播放 HDR/10-bit 视频
- 预期：正常渲染，颜色正确

### 7. VR 视频测试
- 播放 VR 视频
- 预期：双眼立体视差正常

---

## 五、注意事项

1. **编译后测试**: 所有修改已通过语法检查，建议在真机上测试
2. **内存监控**: 使用 Instruments Leaks 工具验证内存泄漏已修复
3. **FFmpeg 构建**: 修复了构建脚本错误，需要重新构建 FFmpeg xcframework
4. **兼容性**: 所有修改保持向后兼容，不影响现有 API

---

**修复日期**: 2026-08-27
**修复内容**: 19 个问题（11 个高危 + 8 个内存泄漏）
**影响范围**: 核心播放引擎、Metal 渲染、构建脚本