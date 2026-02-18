#!/bin/bash
# Scriptik installer for macOS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/usr/local/bin"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Scriptik"

echo ""
echo "  Scriptik Installer"
echo "  ========================"
echo ""

# --- Check macOS ---
if [[ "$(uname)" != "Darwin" ]]; then
    echo "ERROR: Scriptik only works on macOS."
    exit 1
fi
echo "[ok] macOS detected"

# --- Check Python 3 ---
if ! command -v python3 &>/dev/null; then
    echo ""
    echo "ERROR: Python 3 is required."
    echo "Install it with: brew install python3"
    exit 1
fi
echo "[ok] Python 3 found ($(python3 --version 2>&1 | awk '{print $2}'))"

# --- Install script ---
echo ""
if [ -w "$INSTALL_DIR" ]; then
    cp "$SCRIPT_DIR/scriptik-cli" "$INSTALL_DIR/scriptik-cli"
    chmod +x "$INSTALL_DIR/scriptik-cli"
else
    echo "Installing to $INSTALL_DIR requires admin privileges."
    sudo cp "$SCRIPT_DIR/scriptik-cli" "$INSTALL_DIR/scriptik-cli"
    sudo chmod +x "$INSTALL_DIR/scriptik-cli"
fi
echo "[ok] Installed scriptik-cli to $INSTALL_DIR"

# --- Install dashboard ---
DASHBOARD_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/scriptik"
mkdir -p "$DASHBOARD_DIR"
cp "$SCRIPT_DIR/dashboard.py" "$DASHBOARD_DIR/dashboard.py"
echo "[ok] Installed dashboard to $DASHBOARD_DIR"

# --- Create Automator Quick Action ---
WORKFLOW_DIR="$SERVICES_DIR/$WORKFLOW_NAME.workflow/Contents"
mkdir -p "$WORKFLOW_DIR"

cat > "$WORKFLOW_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Scriptik</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
		</dict>
	</array>
</dict>
</plist>
PLIST

cat > "$WORKFLOW_DIR/document.wflow" <<'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>/usr/local/bin/scriptik-cli</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
				</array>
				<key>isViewVisible</key>
				<true/>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceApplicationGroupName</key>
		<string>General</string>
		<key>serviceApplicationPath</key>
		<string></string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

echo "[ok] Created Quick Action workflow"

# --- Run setup (install Whisper, create config, download model) ---
echo ""
"$INSTALL_DIR/scriptik-cli" --setup

# --- Keyboard shortcut instructions ---
echo ""
echo "  Assign a keyboard shortcut"
echo "  --------------------------"
echo ""
echo "  Option A: System Settings (recommended)"
echo "    1. Open System Settings > Keyboard > Keyboard Shortcuts > Services"
echo "    2. Find 'Scriptik' under General"
echo "    3. Click 'none' and press your shortcut (e.g. Ctrl+Shift+R)"
echo ""
echo "  Option B: Shortcuts app"
echo "    1. Open Shortcuts.app > New Shortcut"
echo "    2. Add 'Run Shell Script' action"
echo "    3. Type: scriptik-cli"
echo "    4. Right-click shortcut > Add Keyboard Shortcut"
echo ""

# Offer to open System Settings
read -p "Open Keyboard Shortcuts settings now? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
fi

echo ""
echo "  Installation complete!"
echo ""
