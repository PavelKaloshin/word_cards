.PHONY: build test test-unit test-integration test-ui lint format clean

# Build the iOS app
build:
	xcodebuild -project SerbianCards.xcodeproj \
		-scheme SerbianCards \
		-destination 'platform=iOS Simulator,id=1DE2AEF8-21C4-4E7E-9D6A-4FD203643D59' \
		-configuration Debug \
		build

# Run unit + integration tests (no UI tests)
test:
	xcodebuild -project SerbianCards.xcodeproj \
		-scheme SerbianCards \
		-destination 'platform=iOS Simulator,id=1DE2AEF8-21C4-4E7E-9D6A-4FD203643D59' \
		-configuration Debug \
		test -only-testing:SerbianCardsTests

# Run unit tests only (no integration)
test-unit:
	xcodebuild -project SerbianCards.xcodeproj \
		-scheme SerbianCards \
		-destination 'platform=iOS Simulator,id=1DE2AEF8-21C4-4E7E-9D6A-4FD203643D59' \
		-configuration Debug \
		test -only-testing:SerbianCardsTests/Unit

# Run integration tests
test-integration:
	xcodebuild -project SerbianCards.xcodeproj \
		-scheme SerbianCards \
		-destination 'platform=iOS Simulator,id=1DE2AEF8-21C4-4E7E-9D6A-4FD203643D59' \
		-configuration Debug \
		test -only-testing:SerbianCardsTests/Integration

# Run UI tests (requires API key in simulator)
test-ui:
	xcodebuild -project SerbianCards.xcodeproj \
		-scheme SerbianCards \
		-destination 'platform=iOS Simulator,id=1DE2AEF8-21C4-4E7E-9D6A-4FD203643D59' \
		-configuration Debug \
		test -only-testing:SerbianCardsUITests

# Lint with SwiftLint (if installed)
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint SerbianCards/; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

# Format with swift-format (if installed)
format:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format format --in-place --recursive SerbianCards/ SerbianCardsTests/; \
	else \
		echo "swift-format not installed. Install with: brew install swift-format"; \
	fi

# Clean build artifacts
clean:
	xcodebuild -project SerbianCards.xcodeproj \
		-scheme SerbianCards \
		clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/SerbianCards-*
