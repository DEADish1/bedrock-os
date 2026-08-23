# Bedrock Installer

This directory contains the cross-platform installer foundation. The graphical Windows, macOS, and Linux application will call a small privileged writer only after the unprivileged selection layer validates an exact removable target.

## Safety boundary

\`core/validate-target-selection.sh\` consumes a fresh JSON inventory snapshot and returns the selected target only when all release-blocking rules pass. It never writes to a disk.

\`\`\`sh
sh installer/core/validate-target-selection.sh inventory.json target-id "ERASE model — path — capacity"
\`\`\`

Platform adapters must provide stable target IDs and refresh the inventory immediately before privileged writing. See \`docs/INSTALLER-SAFETY.md\`.
