#!/bin/bash

# Define colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Handle Ctrl+C gracefully
trap ctrl_c INT
function ctrl_c() {
    echo -e "${RED}[!]${NC} Script terminated by user. Cleaning up..."
    exit 1
}

# Add this to check if arduino-cli is installed
check_arduino_cli() {
    if ! command -v arduino-cli > /dev/null 2>&1; then
        echo -e "${RED}[!]${NC} arduino-cli not found. Please install it first."
        echo -e "    Visit: https://arduino.github.io/arduino-cli/latest/installation/"
        exit 1
    fi
}

# Check for required tools
check_tools() {
    echo -e "${YELLOW}[*]${NC} Checking required tools..."
    
    # Check pip
    if ! command -v pip > /dev/null 2>&1; then
        echo -e "${RED}[!]${NC} pip not found. Please install Python and pip first."
        exit 1
    fi
    
    # Check/install ESP tools
    for tool in esptool.py espsecure.py espefuse.py; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            echo -e "${RED}[!]${NC} $tool not found. Installing..."
            pip install esptool
            break
        fi
    done
}

# Check for PEM file
check_pem() {
    if [ ! -f "secure_boot_signing_key.pem" ]; then
        echo -e "${RED}[!]${NC} Error: secure_boot_signing_key.pem not found!"
        echo -e "    Please place your secure boot signing key, named as \"secure_boot_signing_key.pem\", in this directory."
        exit 1
    fi
    echo -e "${GREEN}[✓]${NC} Found secure boot signing key (secure_boot_signing_key.pem)"
}

# Setup binary directory
setup_binary_dir() {
    if [ -d "binary" ]; then
        echo -e "${RED}[!]${NC} Found older \"binary/\" directory. Removing..."
        echo -e "${YELLOW}[*]${NC} Removing existing \"binary/\" directory..."
        rm -rf binary
    fi
    echo -e "${YELLOW}[*]${NC} Creating fresh \"binary/\" directory..."
    mkdir binary
    if [ -d "binary" ]; then
        echo -e "${GREEN}[✓]${NC} Successfully created \"binary/\" directory."
    else
        echo -e "${RED}[!]${NC} Failed to create \"binary/\" directory."
        exit 1
    fi
}

# Get sketch name
get_sketch_name() {
    SKETCH_NAME=$(basename "$PWD")
    echo -e "${YELLOW}[*]${NC} Detected sketch name: $SKETCH_NAME"
    return 0
}

# Compile
compile_sketch() {
    echo -e "${YELLOW}[*]${NC} Ready to compile."
    echo -e "${YELLOW}[*]${NC} Compiling..."
    arduino-cli compile -v --fqbn esp32:esp32:esp32h2:UploadSpeed=921600,CDCOnBoot=default,FlashFreq=64,FlashMode=qio,FlashSize=4M,PartitionScheme=min_spiffs,DebugLevel=none,EraseFlash=all,JTAGAdapter=default,ZigbeeMode=default --output-dir binary .
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!]${NC} Compilation failed!"
        exit 1
    fi
    echo -e "${GREEN}[✓]${NC} Compilation successful"
}

# Sign binaries
sign_binaries() {
    echo -e "${YELLOW}[*]${NC} Signing bootloader..."
    espsecure.py sign_data --version 2 --keyfile secure_boot_signing_key.pem \
        --output "binary/${SKETCH_NAME}.ino.signed.bootloader.bin" \
        "binary/${SKETCH_NAME}.ino.bootloader.bin"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!]${NC} Signing bootloader failed!"
        exit 1
    else
        echo -e "${GREEN}[✓]${NC} Signing bootloader successful"
    fi
    echo -e ""
    echo -e "${YELLOW}[*]${NC} Signing partition table..."
    espsecure.py sign_data --version 2 --keyfile secure_boot_signing_key.pem \
        --output "binary/${SKETCH_NAME}.ino.signed.partitions.bin" \
        "binary/${SKETCH_NAME}.ino.partitions.bin"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!]${NC} Signing partition table failed!"
        exit 1
    else
        echo -e "${GREEN}[✓]${NC} Signing partition table successful"
    fi
    echo -e ""
    echo -e "${YELLOW}[*]${NC} Signing application..."
    espsecure.py sign_data --version 2 --keyfile secure_boot_signing_key.pem \
        --output "binary/${SKETCH_NAME}.ino.signed.bin" \
        "binary/${SKETCH_NAME}.ino.bin"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!]${NC} Signing application failed!"
        exit 1
    else
        echo -e "${GREEN}[✓]${NC} Signing application successful"
    fi
    echo -e ""
    echo -e "${GREEN}[✓]${NC} All binaries signed successfully"
    echo -e ""
}

# Get Arduino ESP32 version path
get_esp32_version_path() {
    local ESP32_PATH="$ARDUINO_PATH/packages/esp32/hardware/esp32"
    if [ ! -d "$ESP32_PATH" ]; then
        echo -e "${RED}[!]${NC} ESP32 Arduino core not found in $ESP32_PATH"
        exit 1
    fi
    
    # Get the first directory (version) in the esp32 folder
    local VERSION=$(ls -1 "$ESP32_PATH" | head -n 1)
    if [ -z "$VERSION" ]; then
        echo -e "${RED}[!]${NC} No ESP32 version found in $ESP32_PATH"
        exit 1
    fi
    
    echo -e "${YELLOW}[*]${NC} Found ESP32 version: $VERSION"
    BOOT_APP_PATH="$ARDUINO_PATH/packages/esp32/hardware/esp32/$VERSION/tools/partitions/boot_app0.bin"
    
    if [ ! -f "$BOOT_APP_PATH" ]; then
        echo -e "${RED}[!]${NC} boot_app0.bin not found at $BOOT_APP_PATH"
        exit 1
    fi
}

# Get/validate port
get_port() {
    local port_to_use=""
    
    # If port provided via command line
    if [ ! -z "$PORT_ARG" ]; then
        if [ -e "$PORT_ARG" ]; then
            port_to_use="$PORT_ARG"
            echo "$port_to_use" > .last_port
        else
            echo -e "${RED}[!]${NC} Error: Specified port $PORT_ARG does not exist"
            exit 1
        fi
    # If no port argument, try last used port
    elif [ -f ".last_port" ]; then
        port_to_use=$(cat .last_port)
        if [ ! -e "$port_to_use" ]; then
            echo -e "${RED}[!]${NC} Error: Last used port $port_to_use no longer exists"
            exit 1
        fi
    else
        echo -e "${RED}[!]${NC} Error: No port specified. Use --port option"
        echo -e "    Example: $0 --port /dev/tty.usbserial-2120"
        exit 1
    fi
    
    # Return just the port value
    echo "$port_to_use"
}


# Function to ensure port is free
release_port() {
    local port="$1"
    echo -e "${YELLOW}[*]${NC} Waiting for port $port to be ready..."
    sleep 3  # Wait for 3 seconds
}


upload_sketch() {
     ARDUINO_PATH="$HOME/Library/Arduino15"
    get_esp32_version_path
    
    # Get port value and store it
    local PORT=$(get_port)
    echo -e "${YELLOW}[*]${NC} Using port: $PORT"
    
    # Release port
    # release_port "$PORT"
    
    # Build upload command
    local UPLOAD_CMD="esptool.py --chip esp32h2 --port $PORT --baud 921600 \
--before default_reset --after hard_reset write_flash -e -z --flash_mode keep \
--flash_freq keep --flash_size 4MB --force \
0x0 binary/${SKETCH_NAME}.ino.signed.bootloader.bin \
0x8000 binary/${SKETCH_NAME}.ino.signed.partitions.bin \
0xe000 $BOOT_APP_PATH \
0x10000 binary/${SKETCH_NAME}.ino.signed.bin"

    echo -e "\n${YELLOW}[*]${NC} Upload command:"
    echo -e "$UPLOAD_CMD"
    echo -e "\nProceed with upload? (y/n)"
    read -r answer
    if [ "$answer" != "y" ]; then
        echo -e "${RED}[!]${NC} Upload cancelled by user"
        exit 1
    fi

    # Wait for port to be available again
    # Try upload with retries
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo -e "${YELLOW}[*]${NC} Upload attempt $attempt of $max_attempts"
        if eval "$UPLOAD_CMD"; then
            echo -e "${GREEN}[✓]${NC} Upload successful!"
            break
        else
            echo -e "${RED}[!]${NC} Upload failed, waiting before retry..."
            sleep 3
            ((attempt++))
            if [ $attempt -gt $max_attempts ]; then
                echo -e "${RED}[!]${NC} Upload failed after $max_attempts attempts"
                exit 1
            fi
        fi
    done
}


# Main execution
clear
echo -e "=== ESP32-H2 Secure Boot Upload Script ==="

# Parse port argument
PORT_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT_ARG="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}[!]${NC} Unknown option: $1"
            exit 1
            ;;
    esac
done

check_arduino_cli
sleep 1
check_tools
sleep 1
check_pem
sleep 1
setup_binary_dir
sleep 1
get_sketch_name
sleep 1
compile_sketch
sleep 1
sign_binaries
sleep 1
upload_sketch

echo -e "${GREEN}[✓]${NC} Process completed successfully!"