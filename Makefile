SIMULATOR ?= platform=iOS Simulator,name=iPhone 15
SCHEME := RizeMobile
PROJECT := RizeMobile.xcodeproj
COVERAGE_THRESHOLD ?= 50
RESULT_BUNDLE := TestResults.xcresult

.PHONY: generate build test lint format ci coverage

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

# RIZ-47: mirrors the CI coverage gate locally. Requires full Xcode (not
# just Command Line Tools) since it needs xcodebuild + xccov.
coverage: generate
	rm -rf $(RESULT_BUNDLE)
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(SIMULATOR)" \
		-enableCodeCoverage YES \
		-resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO
	COVERAGE_THRESHOLD=$(COVERAGE_THRESHOLD) scripts/coverage-check.sh $(RESULT_BUNDLE)
