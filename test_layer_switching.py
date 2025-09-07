#!/usr/bin/env python3
"""
Test script to diagnose layer switching issues in WordTagger
"""

import subprocess
import time
import os
import signal
import sys

def run_app_and_capture_logs():
    """
    Launch the app and capture console logs for layer switching debug messages
    """
    print("🧪 Starting WordTagger layer switching test...")
    
    # Path to the built app
    app_path = "/Users/Patronum/Library/Developer/Xcode/DerivedData/WordTagger-bqhzlwmfphxbxwcobfeszlnokvwo/Build/Products/Debug/Connection.app"
    
    if not os.path.exists(app_path):
        print(f"❌ App not found at: {app_path}")
        return False
    
    # Start log monitoring in the background
    print("📡 Starting log monitoring...")
    log_process = None
    app_process = None
    
    try:
        # Start log monitoring (simplified approach)
        log_cmd = ["log", "stream", "--predicate", "eventMessage CONTAINS 'LayerGraphWindow' OR eventMessage CONTAINS 'switchToLayer' OR eventMessage CONTAINS 'WindowFocusManager'", "--type", "log"]
        log_process = subprocess.Popen(log_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        # Give log monitoring a moment to start
        time.sleep(2)
        
        # Launch the app
        print("🚀 Launching WordTagger...")
        app_process = subprocess.Popen(["open", app_path])
        
        # Wait for app to fully launch
        time.sleep(5)
        
        print("⏳ Monitoring logs for 30 seconds...")
        print("🔧 Please manually test layer switching in the app during this time.")
        print("📋 Steps to test:")
        print("   1. Open a layer graph window (Command+G or menu)")
        print("   2. Try Command+clicking on a layer node")
        print("   3. Check if the main window switches layers")
        print()
        
        # Monitor logs for 30 seconds
        start_time = time.time()
        layer_switch_messages = []
        
        while time.time() - start_time < 30:
            if log_process.poll() is None:
                try:
                    line = log_process.stdout.readline()
                    if line:
                        line = line.strip()
                        if any(keyword in line for keyword in ['LayerGraphWindow', 'switchToLayer', 'WindowFocusManager']):
                            layer_switch_messages.append(line)
                            print(f"📝 {line}")
                except:
                    pass
            time.sleep(0.1)
        
        print(f"\n📊 Captured {len(layer_switch_messages)} relevant log messages")
        
        if layer_switch_messages:
            print("\n🔍 Analysis of captured messages:")
            for msg in layer_switch_messages:
                if "switchToLayer" in msg:
                    print(f"✅ Layer switch attempt: {msg}")
                elif "LayerGraphWindow" in msg:
                    print(f"🔗 Layer graph activity: {msg}")
                elif "WindowFocusManager" in msg:
                    print(f"🏠 Window focus activity: {msg}")
        else:
            print("❌ No layer switching debug messages captured")
            print("💡 This suggests either:")
            print("   - Layer switching was not attempted")
            print("   - Debug messages are not being logged")
            print("   - Log filtering is not working correctly")
    
    except Exception as e:
        print(f"❌ Error during testing: {e}")
        return False
    
    finally:
        # Clean up processes
        if log_process:
            try:
                log_process.terminate()
                log_process.wait(timeout=2)
            except:
                log_process.kill()
        
        if app_process:
            try:
                app_process.terminate()
            except:
                pass
        
        print("\n✅ Test completed")
    
    return True

def analyze_code_structure():
    """
    Analyze the code structure for potential issues
    """
    print("\n🔍 Analyzing code structure for potential issues...")
    
    # Check if key files exist and have the expected methods
    key_files = [
        "/Users/Patronum/Desktop/WordTagger/WordTagger/LayerGraphWindowView.swift",
        "/Users/Patronum/Desktop/WordTagger/WordTagger/WindowFocusManager.swift", 
        "/Users/Patronum/Desktop/WordTagger/WordTagger/WordTaggerApp.swift"
    ]
    
    issues_found = []
    
    for file_path in key_files:
        if not os.path.exists(file_path):
            issues_found.append(f"Missing file: {file_path}")
            continue
            
        try:
            with open(file_path, 'r') as f:
                content = f.read()
                
            if "LayerGraphWindowView.swift" in file_path:
                if "switchToLayerInMainWindow" not in content:
                    issues_found.append("Missing switchToLayerInMainWindow method in LayerGraphWindowView")
                if "getMainWindowId" not in content:
                    issues_found.append("LayerGraphWindowView not using getMainWindowId")
                    
            elif "WindowFocusManager.swift" in file_path:
                if "func getMainWindowId()" not in content:
                    issues_found.append("Missing getMainWindowId method in WindowFocusManager")
                    
            elif "WordTaggerApp.swift" in file_path:
                if "switchToLayer" not in content:
                    issues_found.append("Missing switchToLayer notification handling in WordTaggerApp")
                    
        except Exception as e:
            issues_found.append(f"Error reading {file_path}: {e}")
    
    if issues_found:
        print("❌ Issues found:")
        for issue in issues_found:
            print(f"   - {issue}")
    else:
        print("✅ All key files and methods appear to be present")
    
    return len(issues_found) == 0

if __name__ == "__main__":
    print("🧪 WordTagger Layer Switching Diagnostic Tool")
    print("=" * 50)
    
    # First analyze code structure
    code_ok = analyze_code_structure()
    
    if not code_ok:
        print("\n❌ Code structure issues found. Please fix these first.")
        sys.exit(1)
    
    # Then run the live test
    success = run_app_and_capture_logs()
    
    if success:
        print("\n✅ Test completed successfully")
        print("💡 If layer switching is not working, check the captured debug messages above.")
    else:
        print("\n❌ Test failed")
    
    print("\n🔍 Next steps:")
    print("   1. Review the debug messages above")
    print("   2. Check if window ID mapping is correct")
    print("   3. Verify notification routing logic")
    print("   4. Test with different layer configurations")