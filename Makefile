.PHONY: build install clean

APP_NAME = Record Toggle
BUILD_DIR = RecordToggle/build

build:
	@echo "Building $(APP_NAME)..."
	cd RecordToggle && bash scripts/bundle.sh

install: build
	@echo "Installing $(APP_NAME) to /Applications..."
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" /Applications/
	@echo "Installed. Launch from /Applications or Spotlight."

clean:
	rm -rf RecordToggle/.build RecordToggle/build
	@echo "Cleaned build artifacts."
