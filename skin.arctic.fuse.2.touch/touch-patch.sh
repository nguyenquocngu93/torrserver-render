#!/bin/sh
# ============================================================
#  Arctic Fuse 2 Touch Mod - Patches for touchscreen devices
#  Run this after installing the skin to enable touch mode
# ============================================================

SKIN_DIR="${HOME}/.kodi/addons/skin.arctic.fuse.2.touch"
XML_DIR="$SKIN_DIR/1080i"

echo "==> Arctic Fuse 2 Touch Mod - Patching..."

# 1. Enlarge ButtonMenu touch targets (80x80 -> 140x140)
echo "  [1/5] Enlarging ButtonMenu touch targets..."
sed -i 's|<itemlayout width="100" height="100">|<itemlayout width="140" height="140">|g' "$XML_DIR/Includes_ButtonMenu.xml"
sed -i 's|<focusedlayout width="100" height="100">|<focusedlayout width="140" height="140">|g' "$XML_DIR/Includes_ButtonMenu.xml"

# 2. Enlarge fixedlist containers
echo "  [2/5] Enlarging fixedlist containers..."
sed -i 's|<height>100</height>|<height>140</height>|g' "$XML_DIR/Includes_ButtonMenu.xml"

# 3. Enable mouse/touch in settings
echo "  [3/5] Enabling mouse/touch mode..."
SETTINGS_FILE="$SKIN_DIR/extras/xml/settings.xml"
if [ -f "$SETTINGS_FILE" ]; then
    sed -i 's|<setting id="mouse_enabled" default="false">|<setting id="mouse_enabled" default="true">|g' "$SETTINGS_FILE"
fi

# 4. Create enhanced settings for touch
echo "  [4/5] Creating touch settings..."
cat > "$SKIN_DIR/extras/xml/settings-touch.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<settings>
    <category label="31010">
        <group label="31100">
            <setting id="mouse_enabled" default="true" />
            <setting id="touch_mode" default="1" />
            <setting id="touch_button_size" default="140" />
        </group>
    </category>
</settings>
XML

# 5. Update addon.xml with touch mod info
echo "  [5/5] Updating addon.xml..."
cat > "$SKIN_DIR/addon.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<addon id="skin.arctic.fuse.2.touch" name="Arctic Fuse 2 Touch" version="2.12.11-touch" provider-name="jurialmunkey + Touch Mod">
    <requires>
        <import addon="xbmc.gui.skin" version="5.14.0"/>
        <import addon="resource. skins fonts.arcticaborealis" version="0.0.1"/>
        <import addon="resource.images.color.white" version="0.0.4"/>
        <import addon="script.skinvariables" version="1.0.44"/>
        <import addon="script.jurialmunkey.objectutils" version="0.0.12"/>
        <import addon="script.module.importlib.metadata" version="7.0.1"/>
    </requires>
    <extension point="xbmc.gui.skin" directory="1080i">
        <res>1080i</res>
    </extension>
    <extension point="xbmc.addon.metadata">
        <summary>Arctic Fuse 2 with touch-friendly modifications</summary>
        <description>This is Arctic Fuse 2 skin modified for touchscreen devices. Button sizes enlarged, touch targets increased, mouse/touch mode enabled by default.</description>
        <platform>all</platform>
    </extension>
</addon>
XML

echo ""
echo "==> Touch mod installed successfully!"
echo "    - Button targets: 80px -> 140px"
echo "    - Touch mode: enabled"
echo "    - Mouse support: enabled"
echo ""
echo "To activate: Settings -> Interface -> Skin -> Arctic Fuse 2 Touch"
