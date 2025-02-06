# ESP32 Secure Boot Guide

## Focus hardware chipset

`ESP32-H2`

> But the shell script and commands can be adopted for any ESP32 chipset that supports secure boot

Secure boot ensures that our ESP32-H2 only runs firmware that we have authorized. 

## Advantages

- The RSA-PSS's public key is stored on the device. The corresponding RSA-PSS private key is kept at a secret place and is never accessed by the device.
- Only one public key can be generated and stored in the chip during manufacturing.
- The same image format and signature verification method is applied for applications and the second stage bootloader.
- No secrets are stored on the device. Therefore, it is immune to passive side-channel attacks, e.g., timing or power analysis.

When enabled:

- Only firmware signed with your private key will be accepted
- Prevents unauthorized or malicious code from running
- Protects against firmware tampering and unauthorized updates
- _Once enabled, cannot be disabled (permanent security feature)_

## Key points

- Requires initial setup with a signing key
- All firmware updates must be signed
- Provides hardware-level security
- Essential for IoT devices requiring secure deployments

> 💡 Need local system installation.

## 1. Initial Secure Boot Setup (One Time Only)

1. Generate & Process signing key:

```bash
# In your project directory
# 1. Generate signing key, if it is the first time and we do not have the secure_boot_signing_key.pem
espsecure.py generate_signing_key secure_boot_signing_key.pem

# 2. Process the public key for efuse:
espsecure.py digest_sbv2_public_key --keyfile secure_boot_signing_key.pem --output secure_boot_digest.bin
```

1. Burn the key and enable secure boot:

> 💡 Can’t be un-done !!

```bash
# Set key purpose
espefuse.py --port <PORT> burn_efuse KEY_PURPOSE_0 SECURE_BOOT_DIGEST0

# Burn the key
espefuse.py --port <PORT> burn_key BLOCK_KEY0 secure_boot_digest.bin SECURE_BOOT_DIGEST0

# Enable secure boot
espefuse.py --port <PORT> burn_efuse SECURE_BOOT_EN 1
```

## 2. Compiling (Every Update)

```bash
# Clean binary directory
rm -rf binary
mkdir binary

# Compile
arduino-cli compile -v --fqbn esp32:esp32:esp32h2:UploadSpeed=921600,CDCOnBoot=default,FlashFreq=64,FlashMode=qio,FlashSize=4M,PartitionScheme=min_spiffs,DebugLevel=none,EraseFlash=all,JTAGAdapter=default,ZigbeeMode=default --output-dir binary .
```

## 3. Signing Binaries (Every Update)

```bash
# Sign bootloader
espsecure.py sign_data --version 2 --keyfile secure_boot_signing_key.pem --output binary/<SKETCH_NAME>.ino.signed.bootloader.bin binary/<SKETCH_NAME>.ino.bootloader.bin

# Sign partition table
espsecure.py sign_data --version 2 --keyfile secure_boot_signing_key.pem --output binary/<SKETCH_NAME>.ino.signed.partitions.bin binary/<SKETCH_NAME>.ino.partitions.bin

# Sign application
espsecure.py sign_data --version 2 --keyfile secure_boot_signing_key.pem --output binary/<SKETCH_NAME>.ino.signed.bin binary/<SKETCH_NAME>.ino.bin
```

## 4. Uploading (Every Update)

4.1. From Terminal 

> Can't use `arduino-cli`

```bash
# For esp32-h2, as an example 

esptool.py --chip esp32h2 --port <PORT> --baud 921600 \
--before default_reset --after hard_reset write_flash -e -z --flash_mode keep \
--flash_freq keep --flash_size 4MB --force \
0x0 "binary/<SKETCH_NAME>.ino.signed.bootloader.bin" \
0x8000 "binary/<SKETCH_NAME>.ino.signed.partitions.bin" \
0xe000 "/Users/saurabhdatta/Library/Arduino15/packages/esp32/hardware/esp32/3.0.7/tools/partitions/boot_app0.bin" \
0x10000 "binary/<SKETCH_NAME>.ino.signed.bin"
```

> 💡 Note! if `—-force` is not used, it will show an error: `A fatal error occurred: Secure Boot detected, writing to flash regions < 0x8000 is disabled to protect the bootloader.`
>
> This is expected and good - it shows the secure boot protection is working!
>
> Using `--force` is okay in this case because we're uploading signed binaries.


4.2. From web tool: [dattasaurabh82.github.io/webespflasher/](https://dattasaurabh82.github.io/webespflasher/)

## But that's a lot of manual steps

Yes and so, the manual steps 2 and 4 can be made faster with a helper script called [secure_boot_process.sh](secure_boot_process.sh)

Just do:

```bash
# For esp32-h2, as an example
# Adopt the script and the cmd settings for your chip set 

./secure_boot_process.sh --port <PORT>

# compiles, signs and uploads signed binaries
```
