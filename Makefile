.PHONY: build install clean build-windows setup-windows install-windows clean-windows

APP_NAME = Scriptik
BUILD_DIR = Scriptik/build

# ── macOS ──────────────────────────────────────────────────────────────

build:
	@echo "Building $(APP_NAME) for macOS..."
	cd Scriptik && bash scripts/bundle.sh

install: build
	@echo "Installing $(APP_NAME) to /Applications..."
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" /Applications/
	@echo "Installed. Launch from /Applications or Spotlight."

clean:
	rm -rf Scriptik/.build Scriptik/build Scriptik.Windows/bin Scriptik.Windows/obj Scriptik.Windows/publish
	@echo "Cleaned build artifacts."

# ── Windows ────────────────────────────────────────────────────────────

setup-windows:
	@echo "Setting up Python/Whisper environment for Windows..."
	cd Scriptik.Windows && powershell -ExecutionPolicy Bypass -File Scripts/setup.ps1

build-windows:
	@echo "Building $(APP_NAME) for Windows..."
	cd Scriptik.Windows && powershell -ExecutionPolicy Bypass -File Scripts/build.ps1

install-windows: setup-windows build-windows
	@echo ""
	@echo "$(APP_NAME) for Windows is ready!"
	@echo "  Run: Scriptik.Windows/publish/Scriptik.exe"

clean-windows:
	rm -rf Scriptik.Windows/bin Scriptik.Windows/obj Scriptik.Windows/publish
	@echo "Cleaned Windows build artifacts."