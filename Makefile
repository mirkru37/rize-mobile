SIMULATOR ?= platform=iOS Simulator,name=iPhone 15
SCHEME := RizeMobile
PROJECT := RizeMobile.xcodeproj

.PHONY: generate build test lint format ci

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(SIMULATOR)" \
		CODE_SIGNING_ALLOWED=NO

test: generate
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(SIMULATOR)" \
		CODE_SIGNING_ALLOWED=NO

lint:
	swiftlint --strict
	swiftformat --lint .

format:
	swiftformat .

ci: generate lint build test
