(() => {
  "use strict";

  const guidance = Object.freeze({
    space: Object.freeze({
      code: "insufficient-space",
      title: "This drive does not have enough space.",
      action: "Choose a larger removable drive, then start again.",
    }),
    interrupted: Object.freeze({
      code: "interrupted-write",
      title: "The write was interrupted or incomplete.",
      action: "Reconnect the drive if needed, refresh the drive list, and rewrite it from the beginning.",
    }),
    verification: Object.freeze({
      code: "verification-failed",
      title: "The written data did not pass verification.",
      action: "Rewrite the drive from the beginning. If verification fails again, replace the drive.",
    }),
    unavailable: Object.freeze({
      code: "drive-unavailable",
      title: "The selected drive is no longer safely available.",
      action: "Reconnect or unmount the drive, refresh the drive list, and start again.",
    }),
    approval: Object.freeze({
      code: "approval-not-completed",
      title: "Administrator approval was not completed.",
      action: "Start again and approve the protected write when your computer asks.",
    }),
    progress: Object.freeze({
      code: "invalid-progress",
      title: "The protected progress update was not valid.",
      action: "Wait for the protected writer result. If the operation stops, start again from the beginning.",
    }),
    generic: Object.freeze({
      code: "write-failed",
      title: "Bedrock could not complete this drive.",
      action: "Reconnect the drive, refresh the drive list, and rewrite it from the beginning.",
    }),
  });

  const includesAny = (message, terms) => terms.some(term => message.includes(term));
  const classify = value => {
    const message = String(value || "").toLowerCase();
    if (includesAny(message, ["insufficient capacity", "not enough space", "too small", "undersized", "at least 8 gib"])) return guidance.space;
    if (includesAny(message, ["checksum", "hash mismatch", "verification mismatch", "did not match", "reread"])) return guidance.verification;
    if (includesAny(message, ["interrupted", "incomplete", "short write", "broken pipe", "unexpected end", "disconnected", "disappearing media"])) return guidance.interrupted;
    if (includesAny(message, ["mounted", "read-only", "read only", "busy", "not found", "no longer", "identity change", "capacity change"])) return guidance.unavailable;
    if (includesAny(message, ["approval", "authentication", "permission denied", "not elevated", "cancelled", "canceled"])) return guidance.approval;
    if (includesAny(message, ["progress", "sequence", "malformed", "oversized message"])) return guidance.progress;
    return guidance.generic;
  };

  const messageFor = value => {
    const result = classify(value);
    return `${result.title} ${result.action} Do not boot from or use this drive until Bedrock reports a successful verification.`;
  };

  globalThis.BedrockRecovery = Object.freeze({ classify, messageFor });
})();
