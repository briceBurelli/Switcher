#!/usr/bin/env bash

# ==============================================================================
# Switcher - Build & Package Script
# Produit le bundle macOS natif Switcher.app signé ad-hoc
# ==============================================================================

set -euo pipefail

# Couleurs d'affichage
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

APP_NAME="Switcher"
BUNDLE_ID="com.stack.switcher"
VERSION="1.0.0"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

INSTALL_FLAG=false
RUN_FLAG=false
DMG_FLAG=false

# Traitement des arguments
for arg in "$@"; do
    case $arg in
        --install|-i)
            INSTALL_FLAG=true
            ;;
        --run|-r)
            RUN_FLAG=true
            ;;
        --dmg|-d)
            DMG_FLAG=true
            ;;
        --help|-h)
            echo "Usage: ./build.sh [OPTIONS]"
            echo "Options:"
            echo "  --install, -i   Installe Switcher.app dans /Applications (ou ~/Applications)"
            echo "  --run, -r       Lance Switcher.app après la compilation"
            echo "  --dmg, -d       Compile en universel (Apple Silicon + Intel) et crée Switcher.dmg à partager"
            echo "  --help, -h      Affiche cette aide"
            exit 0
            ;;
    esac
done

echo -e "${PURPLE}======================================================${NC}"
echo -e "${PURPLE}   🪟  Compilation et assemblage de Switcher (macOS)   ${NC}"
echo -e "${PURPLE}======================================================${NC}"

# 1. Compilation Swift Package Manager en mode Release
echo -e "\n${BLUE}[1/5] Compilation Swift en mode Release...${NC}"
cd "${PROJECT_DIR}"
if [ "$DMG_FLAG" = true ]; then
    # Universel : fonctionne aussi sur les Mac Intel
    swift build -c release --arch arm64 --arch x86_64
    BIN_PATH="${PROJECT_DIR}/.build/apple/Products/Release/${APP_NAME}"
else
    swift build -c release
    BIN_PATH="${PROJECT_DIR}/.build/release/${APP_NAME}"
fi
if [ ! -f "${BIN_PATH}" ]; then
    echo -e "${RED}Erreur : Le binaire ${BIN_PATH} n'a pas été généré.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Binaire compilé avec succès : ${BIN_PATH}${NC}"

# 2. Construction de la structure du bundle .app
echo -e "\n${BLUE}[2/5] Création de l'arborescence ${APP_NAME}.app...${NC}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    echo -e "${GREEN}✓ Icône AppIcon.icns intégrée.${NC}"
fi

# 3. Génération du Info.plist
echo -e "\n${BLUE}[3/5] Génération du Info.plist (LSUIElement = true)...${NC}"
cat << EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppSleepDisabled</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Stack. Tous droits réservés.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Switcher affiche un aperçu de chaque fenêtre dans le sélecteur ⌘Tab. Rien n'est enregistré ni envoyé.</string>
</dict>
</plist>
EOF
echo -e "${GREEN}✓ Info.plist généré.${NC}"

# 4. Signature ad-hoc avec requirement stable (évite l'invalidation des permissions à chaque rebuild)
echo -e "\n${BLUE}[4/5] Signature locale du bundle (identifiant stable)...${NC}"
# iCloud Drive (Documents synchronisé) ajoute des attributs Finder que codesign refuse
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - -r="designated => identifier \"${BUNDLE_ID}\"" "${APP_BUNDLE}"
echo -e "${GREEN}✓ Bundle signé avec requirement '${BUNDLE_ID}' : ${APP_BUNDLE}${NC}"

# 5. Déploiement / Installation
echo -e "\n${BLUE}[5/5] Finalisation...${NC}"
if [ "$INSTALL_FLAG" = true ]; then
    TARGET_DIR="/Applications"
    if [ ! -w "$TARGET_DIR" ]; then
        TARGET_DIR="${HOME}/Applications"
        mkdir -p "${TARGET_DIR}"
    fi

    echo -e "${YELLOW}Installation dans ${TARGET_DIR}/${APP_NAME}.app...${NC}"
    # Arrêter l'instance en cours si elle tourne déjà (SIGTERM : Switcher rend ⌘Tab à macOS en partant)
    killall "${APP_NAME}" 2>/dev/null || true
    sleep 0.5

    rm -rf "${TARGET_DIR}/${APP_NAME}.app"
    cp -R "${APP_BUNDLE}" "${TARGET_DIR}/"
    xattr -cr "${TARGET_DIR}/${APP_NAME}.app"
    echo -e "${GREEN}✓ Installé avec succès dans ${TARGET_DIR}/${APP_NAME}.app !${NC}"
    APP_TO_LAUNCH="${TARGET_DIR}/${APP_NAME}.app"
else
    echo -e "${GREEN}✓ Bundle disponible dans : ${APP_BUNDLE}${NC}"
    echo -e "${YELLOW}Conseil : Utilisez './build.sh --install' pour installer dans /Applications.${NC}"
    APP_TO_LAUNCH="${APP_BUNDLE}"
fi

# Image disque à partager : glisser-déposer vers Applications + notice d'installation
if [ "$DMG_FLAG" = true ]; then
    echo -e "\n${BLUE}Création de l'image disque...${NC}"
    # Préparée hors de Documents : iCloud y remet des attributs Finder qui invalident la signature
    DMG_STAGING="$(mktemp -d)"
    DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
    rm -f "${DMG_PATH}"
    cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
    ln -s /Applications "${DMG_STAGING}/Applications"
    cp "${PROJECT_DIR}/Resources/Lisez-moi.txt" "${DMG_STAGING}/Lisez-moi.txt"
    xattr -cr "${DMG_STAGING}"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
    rm -rf "${DMG_STAGING}"
    echo -e "${GREEN}✓ Image disque prête : ${DMG_PATH}${NC}"
fi

if [ "$RUN_FLAG" = true ]; then
    echo -e "\n${PURPLE}🚀 Lancement de Switcher...${NC}"
    open "${APP_TO_LAUNCH}"
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}   🎉 Switcher est prêt ! ⌘Tab affiche désormais vos fenêtres${NC}"
echo -e "${GREEN}======================================================${NC}"
