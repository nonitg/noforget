#!/bin/bash

# NoForget Xcode Project Setup Script
# This script creates the Xcode project properly using xcodegen or manual instructions

echo "=========================================="
echo "NoForget - Xcode Project Setup"
echo "=========================================="
echo ""
echo "Since Xcode project files cannot be reliably generated programmatically,"
echo "please follow these steps to create the project in Xcode:"
echo ""
echo "1. Open Xcode"
echo "2. File > New > Project"
echo "3. Select 'App' under iOS/macOS (Multiplatform)"
echo "4. Configure:"
echo "   - Product Name: NoForget"
echo "   - Team: Your Development Team"
echo "   - Organization Identifier: com.noforget"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "   - Storage: None"
echo "5. Save to: /Users/nonitgupta/develop/noforget"
echo "   (Choose 'Replace' when prompted about existing files)"
echo ""
echo "6. After project is created:"
echo "   - Delete the default ContentView.swift"
echo "   - Add existing files from NoForget/ folder"
echo "   - Add the NoForgetWidget folder as a Widget Extension target"
echo ""
echo "7. Configure Capabilities in Signing & Capabilities:"
echo "   - iCloud (with CloudKit)"
echo "   - Push Notifications"
echo "   - Background Modes (Background fetch, Remote notifications)"
echo ""
echo "8. Replace the generated Info.plist and entitlements with ours"
echo ""
echo "=========================================="
echo ""

# Alternative: Use xcodegen if installed
if command -v xcodegen &> /dev/null; then
    echo "xcodegen detected! Creating project automatically..."
    cd /Users/nonitgupta/develop/noforget
    xcodegen generate
    echo "Project created successfully!"
else
    echo "To automate this process, you can install xcodegen:"
    echo "  brew install xcodegen"
    echo ""
    echo "Then run: xcodegen generate"
fi
