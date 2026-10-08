# diskwatch

Cached whole-disk usage index ([duc](https://duc.zevv.nl)) with growth reports, plus
block-level storage (LVM thin pools, ZFS, Proxmox guest volumes), cleanup hints
(journal, apt, kernels, logs, Docker, snap, vzdump) and a package report with
last-used estimates. Scans run nightly as root from a systemd timer at idle I/O
priority; every report reads the index, so it is instant and works for any user.

```sh
ansible-playbook -i inventory.yml playbook-diskwatch.yml                                 # all hosts in diskwatch_hosts
ansible-playbook -i inventory.yml playbook-diskwatch.yml -e diskwatch_first_scan=true    # also index right away
ansible-playbook -i inventory.yml playbook-diskwatch.yml -t diskwatch_script             # only update the script
```

On a host: `diskwatch report` (what grew), `diskwatch ls /var`, `diskwatch storage`,
`diskwatch cleanup`, `diskwatch pkgs`, `diskwatch ui` (vim keys), `diskwatch help`.

| Variable | Default | |
|---|---|---|
| `diskwatch_state` | `present` | `absent` removes timers and binaries, keeps `/var/lib/diskwatch` |
| `diskwatch_scan_hour` | `3` | nightly scan hour (randomized within 15 min, catches up after downtime) |
| `diskwatch_first_scan` | `false` | start an index when none exists |
| `diskwatch_free_alert_pct` | `10` | alert when a filesystem has less free space |
| `diskwatch_growth_alert_gb` | `5` | alert when a folder grows this much between scans |
| `diskwatch_exclude` | `""` | colon-separated directory names to skip |
| `diskwatch_notify_cmd` | `""` | receives alerts on stdin, e.g. `curl -s -d @- https://ntfy.sh/<topic>`; alerts always go to `journalctl -t diskwatch` |

Scan roots are all mounted local filesystems; bind mounts (e.g. host storage in a
container) are listed by `diskwatch roots` but not scanned, so the host counts them.
VM disks on LVM-thin or ZFS zvols are not files: see `diskwatch storage`.

Tags: `diskwatch`, `diskwatch_install`, `diskwatch_packages`, `diskwatch_script`,
`diskwatch_ui`, `diskwatch_config`, `diskwatch_systemd`, `diskwatch_scan`,
`diskwatch_remove`.

`files/duc-ui-<release>` is duc built with `files/duc_vim_patch.py` (j/k, h/l, g/G,
ctrl-d/u/f/b, `i` info, `?` help). Build it with `linux/build-duc-ui.sh` (Docker), or copy
the release's `duc-ui-<release>-amd64` here as `duc-ui-<release>`. `files/diskwatch` links to
`linux/diskwatch` in the repository.
