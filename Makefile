.PHONY: all build run test clean

all: build

build:
	@chmod +x build.sh
	@./build.sh

run:
	@chmod +x build.sh
	@./build.sh run

test:
	@swiftc -target arm64-apple-macos14.0 -Xcc -ivfsoverlay -Xcc vfs.yaml \
		Sources/Storage/WordStore.swift \
		Sources/Core/PermissionsManager.swift \
		Sources/Core/ObfuscationNormalizer.swift \
		Sources/Core/FuzzyMatcher.swift \
		Sources/Core/WordBufferEngine.swift \
		Sources/Core/ActionDispatcher.swift \
		Tests/EngineTests.swift \
		-o Tests/run_tests && ./Tests/run_tests && rm Tests/run_tests

install: build
	@mkdir -p $(HOME)/Applications
	@rm -rf $(HOME)/Applications/WordBlocker.app
	@cp -R WordBlocker.app $(HOME)/Applications/
	@echo "✅ Installed WordBlocker.app to $(HOME)/Applications"

reveal:
	@open .

clean:
	@rm -rf build WordBlocker.app Tests/run_tests
