.PHONY: build install clean

APP_NAME = Scriptik
BUILD_DIR = Scriptik/build

build:
	@echo "Building $(APP_NAME)..."
	cd Scriptik && bash scripts/bundle.sh

install: build
	@echo "Installing $(APP_NAME) to /Applications..."
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" /Applications/
	@echo "Installed. Launch from /Applications or Spotlight."

clean:
	rm -rf Scriptik/.build Scriptik/build
	@echo "Cleaned build artifacts."
