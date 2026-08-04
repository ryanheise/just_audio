# Just Audio Integration Tests Makefile
#
# This Makefile provides convenient commands for running integration tests
# for the just_audio library HTTP error handling and memory leak fixes.
#
# Can be run from either:
# - Repository root: ~/projects/libraries/flutter_just_audio
# - Example directory: ~/projects/libraries/flutter_just_audio/just_audio/example

.PHONY: help test-all test-simple test-memory test-http test-comprehensive test-runner clean setup devices android ios

# Helper function to determine correct directory
define run_flutter_cmd
	@if [ -f "pubspec.yaml" ] && [ -d "integration_test" ]; then \
		$(1); \
	elif [ -f "just_audio/example/pubspec.yaml" ]; then \
		cd just_audio/example && $(1); \
	else \
		echo "❌ Could not find just_audio example directory. Please run from repository root or just_audio/example"; \
		exit 1; \
	fi
endef

# Default target
help:
	@echo "Just Audio Integration Tests"
	@echo "============================"
	@echo ""
	@echo "Available commands:"
	@echo "  make setup           - Install dependencies and prepare for testing"
	@echo "  make devices         - List available devices for testing"
	@echo "  make test-all        - Run all integration tests (recommended)"
	@echo "  make test-simple     - Run simple platform-agnostic tests"
	@echo "  make test-runner     - Run main test suite with comprehensive reporting"
	@echo "  make test-memory     - Run memory leak prevention tests"
	@echo "  make test-http       - Run HTTP error handling tests"
	@echo "  make test-comprehensive - Run combined stress tests"
	@echo "  make android         - Run tests on Android device/emulator"
	@echo "  make ios             - Run tests on iOS device/simulator"
	@echo "  make clean           - Clean build artifacts and cache"
	@echo ""
	@echo "Examples:"
	@echo "  make setup && make test-simple    # Quick setup and test"
	@echo "  make android                      # Test on Android"
	@echo "  make test-memory                  # Memory leak tests only"

# Setup dependencies and prepare for testing
setup:
	@echo "🔧 Setting up Just Audio integration tests..."
	@if [ -f "pubspec.yaml" ]; then \
		flutter pub get; \
	elif [ -f "just_audio/example/pubspec.yaml" ]; then \
		cd just_audio/example && flutter pub get; \
	else \
		echo "❌ Could not find pubspec.yaml. Please run from just_audio/example directory or repository root"; \
		exit 1; \
	fi
	@echo "✅ Dependencies installed"
	@echo "📱 Make sure you have a device connected or emulator running"
	@echo "   Run 'make devices' to see available devices"

# List available devices
devices:
	@echo "📱 Available devices for testing:"
	@if [ -f "pubspec.yaml" ]; then \
		flutter devices; \
	elif [ -f "just_audio/example/pubspec.yaml" ]; then \
		cd just_audio/example && flutter devices; \
	else \
		flutter devices; \
	fi

# Run all integration tests (recommended)
test-all: setup
	@echo "🚀 Running all Just Audio integration tests..."
	@echo "This will run comprehensive tests including memory leak prevention and HTTP error handling"
	$(call run_flutter_cmd,flutter test integration_test/test_runner.dart)
	@echo ""
	@echo "🎉 All integration tests completed!"
	@echo "If tests failed, try 'make test-simple' for platform-agnostic testing"

# Run simple platform-agnostic tests
test-simple: setup
	@echo "🧪 Running simple integration tests (platform-agnostic)..."
	@echo "These tests are more robust across different environments"
	$(call run_flutter_cmd,flutter test integration_test/simple_integration_test.dart)
	@echo ""
	@echo "✅ Simple integration tests completed!"

# Run main test suite with comprehensive reporting
test-runner: setup
	@echo "📊 Running main test suite with comprehensive reporting..."
	flutter test integration_test/test_runner.dart
	@echo ""
	@echo "📋 Test runner completed!"

# Run memory leak prevention tests
test-memory: setup
	@echo "🧠 Running memory leak prevention tests..."
	@echo "Testing 20-50 cycles of AudioPlayer create/dispose operations"
	flutter test integration_test/memory_leak_test.dart
	@echo ""
	@echo "✅ Memory leak tests completed!"

# Run HTTP error handling tests
test-http: setup
	@echo "🌐 Running HTTP error handling tests..."
	@echo "Testing LockCachingAudioSource error conversion and stream propagation"
	flutter test integration_test/http_error_handling_test.dart
	@echo ""
	@echo "✅ HTTP error handling tests completed!"

# Run comprehensive stress tests
test-comprehensive: setup
	@echo "💪 Running comprehensive stress tests..."
	@echo "Combined memory leak and error handling validation"
	flutter test integration_test/comprehensive_integration_test.dart
	@echo ""
	@echo "✅ Comprehensive stress tests completed!"

# Run tests on Android device/emulator
android: setup
	@echo "🤖 Running integration tests on Android..."
	@echo "Make sure Android device/emulator is connected"
	$(call run_flutter_cmd,flutter test integration_test/test_runner.dart -d android)
	@echo ""
	@echo "✅ Android integration tests completed!"

# Run tests on iOS device/simulator
ios: setup
	@echo "🍎 Running integration tests on iOS..."
	@echo "Make sure iOS device/simulator is connected"
	flutter test integration_test/test_runner.dart -d ios
	@echo ""
	@echo "✅ iOS integration tests completed!"

# Clean build artifacts and cache
clean:
	@echo "🧹 Cleaning build artifacts and cache..."
	flutter clean
	rm -rf build/
	rm -rf .dart_tool/
	@echo "✅ Clean completed!"

# Advanced testing commands
test-verbose: setup
	@echo "🔍 Running tests with verbose output..."
	flutter test integration_test/test_runner.dart --verbose

test-specific-device: setup
	@echo "📱 Running tests on specific device..."
	@echo "Available devices:"
	@flutter devices
	@echo ""
	@echo "Usage: flutter test integration_test/test_runner.dart -d <device_id>"

# Development helpers
test-quick: setup
	@echo "⚡ Running quick smoke tests..."
	flutter test integration_test/simple_integration_test.dart --name "AudioPlayer basic functionality"

test-error-handling: setup
	@echo "🚨 Running error handling tests only..."
	flutter test integration_test/simple_integration_test.dart --name "Error handling"

test-memory-quick: setup
	@echo "🧠 Running quick memory tests..."
	flutter test integration_test/simple_integration_test.dart --name "Memory leak prevention"

# CI/CD friendly commands
ci-test: setup
	@echo "🤖 Running CI-friendly integration tests..."
	@echo "Using simple tests for better CI compatibility"
	flutter test integration_test/simple_integration_test.dart --reporter=json > test_results.json || true
	@echo "Test results saved to test_results.json"

# Help for specific test categories
help-memory:
	@echo "Memory Leak Prevention Tests"
	@echo "============================"
	@echo "These tests verify that AudioPlayer instances can be created and disposed"
	@echo "repeatedly without causing memory leaks. Tests include:"
	@echo "  • Basic create/dispose cycles (20 cycles)"
	@echo "  • LockCachingAudioSource stress testing (15 cycles)"
	@echo "  • Rapid create/dispose stress test (50 cycles)"
	@echo "  • Memory leak testing with error scenarios"
	@echo ""
	@echo "Run with: make test-memory"

help-http:
	@echo "HTTP Error Handling Tests"
	@echo "========================="
	@echo "These tests verify that HTTP errors from LockCachingAudioSource are"
	@echo "properly converted to PlayerException and propagated through error streams:"
	@echo "  • HTTP 404 error handling"
	@echo "  • Network connectivity error handling"
	@echo "  • Error stream consistency verification"
	@echo "  • HTTP client timeout configuration testing"
	@echo ""
	@echo "Run with: make test-http"

help-comprehensive:
	@echo "Comprehensive Integration Tests"
	@echo "==============================="
	@echo "These tests combine memory leak prevention with error handling to ensure"
	@echo "robust operation under stress conditions:"
	@echo "  • 25-cycle combined stress test"
	@echo "  • Resource cleanup verification"
	@echo "  • Multi-player error propagation testing"
	@echo ""
	@echo "Run with: make test-comprehensive"

# Version and environment info
info:
	@echo "Just Audio Integration Test Environment"
	@echo "======================================"
	@echo "Flutter version:"
	@flutter --version
	@echo ""
	@echo "Available devices:"
	@flutter devices
	@echo ""
	@echo "Test files:"
	@ls -la integration_test/
