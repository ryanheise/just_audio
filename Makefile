.PHONY: help test

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

help: ## Show available commands
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-30s\033[0m %s\n", $$1, $$2}'

test: ## Run all integration tests (comprehensive)
	@echo "🚀 Running all Just Audio integration tests..."
	@if [ -f "just_audio/example/pubspec.yaml" ]; then \
		cd just_audio/example && flutter pub get; \
	fi
	$(call run_flutter_cmd,flutter test integration_test/test_runner.dart)
	@echo "🎉 All integration tests completed!"
