# Filesystem capacity

The capacity section lists root, swap and every local on-disk filesystem from `df -P -k -l -T`, without pseudo or network filesystems, and one entry per device.

## Sub-features

- `capacity-list` parsed filesystems from `df`.
- `capacity-dedupe` subvolumes on one device shown once.

## How to get to it (user POV)

- Open the dashboard and read the capacity section.

## Driving it with sample.sh

Preconditions:

- Doctor passes.

- **Sample.** Run `sample.sh /tmp/vsm-cap`.
- **Proof.** `jq .filesystems /tmp/vsm-cap/model.json` has `/` once, and no `tmpfs` or `overlay` entry, although `/tmp/vsm-cap/df.txt` has them.

## Gotchas

- Btrfs subvolumes on blade share one device; expect one entry for them.
