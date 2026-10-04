# Appearance

Admin → Appearance offers Classic colors, an optional palette based on the
frontend before the Bootstrap 5 migration. The current palette remains the
default. Changing the palette retains the current layout and functionality.
The setting applies to everyone using this installation, including its tenants.
It changes colors, not every visual aspect of the former frontend.

An administrator can tick or untick Classic colors and choose Save appearance.
Saving follows the configured `defanged_admin` role and requires a session
request token. A successful save is also written to User Activity Log when
logging is available. Open pages update within 30 seconds, when a tab becomes
visible, or on reload. Saving remains explicit; toggling the checkbox alone does
not change other users' appearance.

The server saves its preference in `netdisco-appearance.json` under
`NETDISCO_HOME` (or the web process user's home). It uses a private temporary file,
an exclusive lock and atomic replacement. This file must be writable by the web
process and retained during upgrades. For several web hosts, configure
`appearance_settings_file` to one shared writable path. Without a saved file,
the current palette is used. No database migration is required.

The palette uses scoped CSS overrides for standard Netdisco components; new
components may require further rules. Browser controls, third-party tools and
map canvas drawing do not all have a corresponding classic color override.
