# 构建失败修复清单

## 错误类型统计
- **编译错误**: 0 个
- **链接错误**: 0 个
- **其他错误**: 1 个（SwiftPM 构建图冲突）

## 详细错误列表

### P0（阻断性）：PlayerView.swift 文件名重复

**错误信息**:
```
error: couldn't build .../KSPlayer.build/PlayerView.swift.o because of multiple
producers: Compiling Swift Module 'KSPlayer' (71 sources), Compiling Swift Module 'KSPlayer' (71 sources)
```

**根因**:
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift` (旧代码) → 实际不叫 PlayerView
- `Sources/KSPlayer/Feature/Player/Presentation/View/PlayerView.swift` (新代码) → SwiftUI 视图

SwiftPM 将同名文件映射到同一个 `.o` 文件，触发冲突。

**修复方案**:
重命名 `Sources/KSPlayer/Feature/Player/Presentation/View/PlayerView.swift` 为 `FeaturePlayerView.swift`

---

### P1：LogLevel 类型重声明

**位置冲突**:
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:556` → `public enum LogLevel: Int32`
- `Sources/KSPlayer/Core/Logger.swift:13` → `enum LogLevel: Int, CaseIterable`

**修复方案**:
将 `Sources/KSPlayer/Core/Logger.swift` 中的 `enum LogLevel` 改名为 `LoggerLevel`

---

## 优先级排序

| 优先级 | 问题 | 文件 | 修复动作 |
|--------|------|------|----------|
| P0 | PlayerView.swift 文件名冲突 | Feature/.../PlayerView.swift | 重命名为 FeaturePlayerView.swift |
| P1 | LogLevel 类型冲突 | Core/Logger.swift | 改名为 LoggerLevel |

## 修复命令

```bash
# 1. 重命名 PlayerView.swift
git mv Sources/KSPlayer/Feature/Player/Presentation/View/PlayerView.swift Sources/KSPlayer/Feature/Player/Presentation/View/FeaturePlayerView.swift

# 2. 修改 LogLevel 为 LoggerLevel
sed -i 's/enum LogLevel/enum LoggerLevel/g' Sources/KSPlayer/Core/Logger.swift
sed -i 's/\.debug/.debug/g' Sources/KSPlayer/Core/Logger.swift
sed -i 's/LogLevel\.debug/LoggerLevel.debug/g' Sources/KSPlayer/Core/Logger.swift
sed -i 's/LogLevel\.info/LoggerLevel.info/g' Sources/KSPlayer/Core/Logger.swift
sed -i 's/LogLevel\.warning/LoggerLevel.warning/g' Sources/KSPlayer/Core/Logger.swift
sed -i 's/LogLevel\.error/LoggerLevel.error/g' Sources/KSPlayer/Core/Logger.swift
sed -i 's/LogLevel\.verbose/LoggerLevel.verbose/g' Sources/KSPlayer/Core/Logger.swift

# 3. 提交修复
git add -A
git commit -m "fix: 修复 SwiftPM 构建图冲突 - 重命名重复文件和类型

- 重命名 FeaturePlayerView.swift（避免与旧代码 PlayerView.swift 冲突）
- 重命名 LogLevel 为 LoggerLevel（避免与 KSOptions.LogLevel 冲突）"
git push origin ios26-ffmpeg-upgrade
```

## 根因分析

本次失败由重构提交 `586fd78` 引入，而非编译器错误：
- FFmpeg 版本检查已通过（avcodec=60, avformat=60, avfilter=9）
- SwiftPM 在类型检查前因「multiple producers」终止
- 问题仅涉及文件名和类型名冲突，无代码逻辑错误

## 验证清单

修复后需验证：
- [ ] SwiftPM 编译通过
- [ ] 无文件名冲突
- [ ] 无类型名冲突
- [ ] FFmpeg 版本检查通过
- [ ] IPA 构建成功