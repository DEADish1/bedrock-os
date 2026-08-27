# Create Bedrock installation media

Bedrock's signed ISO is the source for bootable USB and optical media. Keep the downloaded ISO, `manifest.json`, and `manifest.p7s` together so Bedrock Installer can verify the filename, size, checksum, and release signature.

## USB drive — preferred

1. Open Bedrock Installer on Windows, macOS, or Linux.
2. Choose the signed ISO or compressed USB image.
3. Select an eligible removable drive of at least 8 GiB.
4. Confirm the exact drive name and let writing, rereading, and verification finish.
5. Remove the drive only after Bedrock reports success or says synchronized media is safe to remove.

If writing is interrupted or verification fails, do not boot from or reuse the incomplete contents. Reconnect the drive and rewrite it from the beginning. Replace media that repeatedly fails verification.

## DVD or CD

USB is faster and is Bedrock's preferred installation method. Bedrock Installer does not control optical drives or burn discs.

1. Verify the signed ISO with Bedrock Installer before burning it.
2. Confirm the ISO fits on one blank disc. A CD will usually be too small; do not split the image across discs. Use a DVD or larger supported optical format when required.
3. In trusted disc-burning software, choose **Burn disc image**, **Write image**, or the equivalent. Do not create a data disc containing the `.iso` file.
4. Use the burner's final verification option when available.
5. Boot the server from its UEFI optical-drive entry.

Optical boot support varies by server firmware and drive. A successful burn does not complete Bedrock's physical-hardware acceptance requirement; the release must still be boot-tested on supported systems.

## Safety and recovery

- A Bedrock success screen means the USB data was flushed, reread, and matched to the signed release checksum.
- Any error means the target has not been accepted as bootable media, even if a progress bar was nearly complete.
- For an undersized drive, select larger media.
- For a busy, mounted, read-only, disconnected, or changed drive, correct the condition, refresh the list, and start again.
- For repeated checksum failures, replace the drive or disc and download the signed image again.
