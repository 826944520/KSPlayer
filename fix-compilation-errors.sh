#!/bin/bash
# 批量修复编译错误
# 基于 GitHub Actions 构建失败分析

set -e

echo "🔧 开始批量修复编译错误..."

# 1. 修复 KSPictureInPictureController.swift 缺失的 }
echo "1️⃣  修复 KSPictureInPictureController.swift..."
FILE="Sources/KSPlayer/AVPlayer/KSPictureInPictureController.swift"
if [ -f "$FILE" ]; then
  # 在 stop() 方法中添加缺失的 }
  sed -i.bak '51 a\    }' "$FILE"
  rm "$FILE.bak"
  echo "✅ 已修复"
else
  echo "❌ 文件不存在"
fi

# 2. 修复 DependencyContainer.swift 重复的 makeRouter()
echo "2️⃣  修复 DependencyContainer.swift..."
FILE="Sources/KSPlayer/Core/DependencyContainer.swift"
if [ -f "$FILE" ]; then
  # 删除第 184-186 行的重复定义
  sed -i.bak '184,186d' "$FILE"
  rm "$FILE.bak"
  echo "✅ 已修复"
else
  echo "❌ 文件不存在"
fi

# 3. 在 Protocols.swift 中添加 CacheRepositoryProtocol
echo "3️⃣  添加 CacheRepositoryProtocol 定义..."
FILE="Sources/KSPlayer/Core/Protocols.swift"
if [ -f "$FILE" ]; then
  # 在文件末尾添加协议定义
  cat >> "$FILE" << 'EOF'

/// 缓存仓库协议
protocol CacheRepositoryProtocol {
    /// 获取缓存媒体
    func getCachedMedia(url: URL) async -> MediaItem?

    /// 获取缓存大小
    func getCacheSize() async throws -> Int64

    /// 清空缓存
    func clearCache() async throws

    /// 预加载媒体
    func preloadMedia(url: URL) async throws
}
EOF
  echo "✅ 已添加"
else
  echo "❌ 文件不存在"
fi

# 4. 修复 Protocols.swift 中的 AudioFormat
echo "4️⃣  修复 AudioFormat 类型..."
FILE="Sources/KSPlayer/Core/Protocols.swift"
if [ -f "$FILE" ]; then
  sed -i.bak 's/format: AudioFormat/format: AVAudioFormat/g' "$FILE"
  sed -i.bak '1 i import AVFoundation' "$FILE"
  rm "$FILE.bak"
  echo "✅ 已修复"
else
  echo "❌ 文件不存在"
fi

# 5. 修复 PlaceholderImplementations.swift 的 import
echo "5️⃣  修复 PlaceholderImplementations.swift import..."
FILE="Sources/KSPlayer/Core/PlaceholderImplementations.swift"
if [ -f "$FILE" ]; then
  sed -i.bak '1 a import Combine\nimport Metal' "$FILE"
  rm "$FILE.bak"
  echo "✅ 已修复"
else
  echo "❌ 文件不存在"
fi

# 6. 修复 CacheRepositoryProtocol 的 cacheService 属性
echo "6️⃣  修复 CacheRepository 的 cacheService 属性..."
FILE="Sources/KSPlayer/Core/PlaceholderImplementations.swift"
if [ -f "$FILE" ]; then
  # 在 CacheRepository 类中添加 cacheService 属性
  sed -i.bak '/final class CacheRepository: CacheRepositoryProtocol {/,/^}/ {
    /private let networkMonitor/ a\
\
    private let cacheService: CacheServiceProtocol
  }' "$FILE"
  rm "$FILE.bak"
  echo "✅ 已修复"
else
  echo "❌ 文件不存在"
fi

echo ""
echo "✅ 所有修复已完成"
echo ""
echo "📝 修改摘要："
echo "  - 修复 KSPictureInPictureController.swift 缺失的 }"
echo "  - 删除 DependencyContainer.swift 重复的 makeRouter()"
echo "  - 添加 CacheRepositoryProtocol 定义"
echo "  - 修复 AudioFormat → AVAudioFormat"
echo "  - 添加 PlaceholderImplementations.swift 的 import"
echo "  - 修复 CacheRepository 的 cacheService 属性"
echo ""
echo "🚀 可以提交这些修复了"