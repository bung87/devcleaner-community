#!/bin/bash

# ============================================================================
# Clean Install Script - 完全卸载应用，模拟首次安装环境
# ============================================================================

set -e

echo "=== DevCleaner Clean Install ==="
echo ""

# 1. 终止运行中的应用
echo "1. Stopping application..."
if pgrep -f "DevCleaner" > /dev/null; then
    pkill -f "DevCleaner" || true
    sleep 2
fi

# 2. 删除应用
echo "2. Removing application..."
if [ -d "/Applications/DevCleaner.app" ]; then
    sudo rm -rf "/Applications/DevCleaner.app"
    echo "   ✓ Removed /Applications/DevCleaner.app"
else
    echo "   ℹ App not found in /Applications"
fi

# 3. 删除用户数据
echo "3. Removing user data..."
rm -rf ~/Library/Application\ Support/DevCleaner
rm -rf ~/Library/Logs/DevCleaner
rm -f ~/Library/Preferences/com.example.devcleaner.plist
rm -rf ~/Library/Containers/com.example.devcleaner  # Sandbox 容器（如果用 Sandbox 测试过）
echo "   ✓ Removed user data"

# 4. 删除 pkg 安装记录（可选，通常不需要）
echo "4. Checking pkg receipt..."
if pkgutil --pkgs | grep -q "com.example.devcleaner"; then
    echo "   Found pkg receipt, removing..."
    sudo pkgutil --forget com.example.devcleaner || true
    echo "   ✓ Removed pkg receipt"
else
    echo "   ℹ No pkg receipt found"
fi

# 5. 清理构建缓存（可选）
echo "5. Cleaning build caches..."
rm -rf build/macos/Release/Mac\ Dev\ Cleaner.app || true
echo "   ✓ Cleaned build caches"

echo ""
echo "=== Clean Install Complete ==="
echo ""
echo "Next steps:"
echo "  1. Build: nimble build"
echo "  2. Package: ./scripts/build.sh"
echo "  3. Install: open \"build/macos/Release/DevCleaner.app\""