VERSION := $(shell cat VERSION)
GO ?= go
NATIVE_INCLUDES := -I native/core -I native/migration -I native/integrations/codex -I native/integrations/secretive

.PHONY: all test test-auto install install-auto brew-package dmg clean
all: build/kcl
	./build/kcl build

build/kcl: $(wildcard cmd/kcl/*.go) VERSION go.mod
	mkdir -p build
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags '-X main.version=$(VERSION)' -o $@ ./cmd/kcl

test:
	$(GO) test -race ./...
	$(GO) vet ./...
	mkdir -p build
	xcrun clang $(NATIVE_INCLUDES) -fobjc-arc -Wno-deprecated-declarations -framework Foundation -framework Security -framework CryptoTokenKit compatibility/check-ssh.m -o build/check-ssh
	./build/check-ssh

test-auto: all
	KCL_TEST_AUTO=1 $(GO) test ./cmd/kcl -run 'TestAutomaticFixture|TestWatcherStopsWithOwner' -count=1 -v

install: all
	./build/kcl install

install-auto: build/kcl
	./build/kcl install-auto

dmg: all
	./build/kcl dmg

brew-package: build/kcl
	./build/kcl brew-package

clean:
	rm -rf 'build/Keychain Compatibility Layer.app' build/kcl build/check
