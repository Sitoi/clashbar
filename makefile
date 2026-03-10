SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS_DIR := $(ROOT_DIR)/Scripts
BUILD_DIR := $(ROOT_DIR)/.build
DIST_DIR := $(ROOT_DIR)/dist
SWIFTPM_DIR := $(ROOT_DIR)/.swiftpm
PACKAGES_DIR := $(ROOT_DIR)/Packages

APP_NAME ?= ClashBar
APP_VERSION ?= 0.1.0
BUILD_NUMBER ?= 1
TARGET_ARCH ?=
DMG_SUFFIX ?=
DMG_VOLUME_NAME ?= $(APP_NAME)
WITH_CORE ?= 0

.PHONY: help build dist dmg clean

help:
	@printf "%s\n" \
		"ClashBar Makefile" \
		"" \
		"Targets:" \
		"  make build        Build dist/$(APP_NAME).app (default: no core)" \
		"  make dist         Build app + dmg (default: no core)" \
		"  make dmg          Build dmg from existing dist/$(APP_NAME).app" \
		"  make clean        Remove .build, dist, .swiftpm and Packages" \
		"" \
		"Overrides:" \
		"  WITH_CORE=1       Bundle mihomo core into the app/dmg" \
		"  TARGET_ARCH=...   Pass through to Swift build/package scripts" \
		"  APP_VERSION=...   Version used for Info.plist and dmg naming" \
		"  BUILD_NUMBER=...  Build number used for Info.plist" \
		"  DMG_SUFFIX=...    Optional dmg filename suffix"

build:
	APP_NAME="$(APP_NAME)" \
	APP_VERSION="$(APP_VERSION)" \
	BUILD_NUMBER="$(BUILD_NUMBER)" \
	TARGET_ARCH="$(TARGET_ARCH)" \
	PREPARE_MIHOMO_BINARY="$(WITH_CORE)" \
	BUNDLE_MIHOMO_BINARY="$(WITH_CORE)" \
	REQUIRE_MIHOMO_BINARY="$(WITH_CORE)" \
	"$(SCRIPTS_DIR)/build.sh" app

dist:
	APP_NAME="$(APP_NAME)" \
	APP_VERSION="$(APP_VERSION)" \
	BUILD_NUMBER="$(BUILD_NUMBER)" \
	TARGET_ARCH="$(TARGET_ARCH)" \
	DMG_SUFFIX="$(DMG_SUFFIX)" \
	DMG_VOLUME_NAME="$(DMG_VOLUME_NAME)" \
	PREPARE_MIHOMO_BINARY="$(WITH_CORE)" \
	BUNDLE_MIHOMO_BINARY="$(WITH_CORE)" \
	REQUIRE_MIHOMO_BINARY="$(WITH_CORE)" \
	"$(SCRIPTS_DIR)/build.sh" all

dmg:
	APP_NAME="$(APP_NAME)" \
	APP_VERSION="$(APP_VERSION)" \
	DMG_SUFFIX="$(DMG_SUFFIX)" \
	DMG_VOLUME_NAME="$(DMG_VOLUME_NAME)" \
	"$(SCRIPTS_DIR)/make_dmg.sh"

clean:
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)" "$(SWIFTPM_DIR)" "$(PACKAGES_DIR)"
