# Bedrock first-run setup

Bedrock opens a guided setup screen on the server's local console the first time an installed system starts. The wizard does not require a terminal command and does not save anything until the final review is accepted.

## Settings

The wizard configures:

- a lowercase server hostname;
- one new administrator account and display name;
- a password or passphrase of at least 12 characters;
- one detected network interface using automatic DHCP or static IPv4 settings;
- optional IPv4 DNS servers;
- an installed time zone and automatic clock synchronization; and
- automatic checks for signed Bedrock update metadata, which never install updates automatically.

IPv6 remains enabled automatically through NetworkManager. A custom static IPv6 address is not part of the 0.3 wizard.

## Safety and recovery

The password is converted to a SHA-512 system password hash in memory. Plaintext password material is never written to the configuration or completion record, and the temporary root-only configuration is removed after setup.

Before applying settings, Bedrock validates the complete configuration and shows a secret-free review. Applying is transactional: if account, hostname, time, network activation, or update preference setup fails, Bedrock attempts to restore the previous values and removes the new account and network profile. The wizard can then be run again from the local console.

After a successful run, Bedrock stores a root-only, secret-free completion record at `/var/lib/bedrock/setup/complete.json`. This prevents automatic first-run setup from launching again.

## Acceptance status

Automated tests cover DHCP and static IPv4 setup, invalid and indirect input rejection, secure file permissions, password redaction, repeat-run refusal, and forced network-activation rollback. The 0.3 release gate still requires the updated image to pass a real local-console setup on an approved disposable installation target.
