.PHONY: project build test lint format clean

project: ## Generate Polka.xcodeproj from project.yml
	xcodegen generate

build: project ## Build a Release app into build/
	xcodebuild -project Polka.xcodeproj -scheme Polka -configuration Release \
		-derivedDataPath build -destination 'generic/platform=macOS' build

test: ## Run unit tests
	swift test --package-path Packages/PolkaKit

lint: ## Check formatting
	swift format lint --strict --recursive App Packages

format: ## Fix formatting
	swift format --in-place --recursive App Packages

clean:
	rm -rf build Polka.xcodeproj Packages/PolkaKit/.build
