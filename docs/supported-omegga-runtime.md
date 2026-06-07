# Supported Omegga Runtime

The Brickadia server wrapper is spelled **Omegga**. When BMF documentation says
Omegga, it means the BMF-supported Windows fork unless the text explicitly says
upstream Omegga.

Use this fork for the Windows-supported BMF/Omegga runtime:

```text
https://github.com/Ty-lerCox/bmf-omegga-fork
```

Do not substitute the stock upstream Omegga package from npm or
`brickadia-community/omegga` for the Windows runtime. Upstream Omegga is
Linux/WSL-oriented and is not the supported Windows tooling for this BMF path.

The supported fork intentionally trails the latest upstream Omegga builds. Treat
that version skew as part of the runtime contract: BMF Windows bridge templates,
UE4SS staging, `OmeggaBridge`, and the helper scripts are validated against the
forked runtime, not against the newest upstream Omegga release.

For non-Windows or generic Omegga plugin development, upstream Omegga
documentation may still be useful. For BMF Windows server automation, install,
run, debug, and report issues against the fork above.
