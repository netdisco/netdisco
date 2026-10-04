# Web color palette

Configuration reference entry for the [Configuration wiki](https://github.com/netdisco/netdisco/wiki/Configuration), under Web Frontend settings.

## `web_color_palette`

Value: `new|classic`. Default: `new`.

Selects the color palette used by the web interface for all users of the configured deployment.

The standard (`new`) palette uses the colors supplied by the updated Bootstrap library. The `classic` palette provides the original Netdisco colors for users who prefer the previous appearance. This setting changes colors only; layout and functionality remain the same.

To enable the classic palette, add this to `deployment.yml`:

```yaml
web_color_palette: classic
```

Set it to `new`, or remove the override, to return to the standard palette. Restart the web service after changing this setting unless your deployment automatically reloads configuration changes. Reload open pages to apply the palette.

The page template loads the Classic stylesheet only when `classic` is selected. No additional plugin or web-writable preference file is required. Configure each web host consistently when using several hosts.

The Classic stylesheet covers standard Netdisco components. Native browser controls, third-party tools, and map canvas drawing are not all restored to the original colors. New components may require additional palette rules.
