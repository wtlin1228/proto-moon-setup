# moonrepo infra survey

A minimal project using proto, moon and pnpm, plus a Dockerfile that bakes the
toolchain into an image so moon tasks run without downloading tools again.

Versions used here reuse what is already installed under `~/.proto`:
proto 0.62.3, moon 2.5.5, node 22.13.0, pnpm 12.2.1.

## Part 1. The project

### Step 1. Initialise the directory

Moon expects a git repo.

```bash
cd ~/wtlin/moonrepo-infra-survey
git init
printf '.moon/cache/\nnode_modules/\n' > .gitignore
git add .gitignore && git commit -m "init"
```

Moon runs `git` to find changed files, so the repo needs at least one commit
or every `moon` command fails with `ambiguous argument 'HEAD'`.

**Checklist**

- [x] `git status` works
- [x] A `.git/` directory exists in the project root
- [x] `git log --oneline` shows at least one commit
- [x] `.gitignore` contains `.moon/cache/`

### Step 2. Pin proto and moon in `.prototools`

This file is for tools that moon does not manage itself. Node and pnpm go in
moon's own config in the next step.

```toml
proto = "0.62.3"
moon = "2.5.5"

[settings]
telemetry = false
```

**Checklist**

- [x] `.prototools` exists at the repo root
- [x] `proto` and `moon` are pinned to exact versions, not `latest`
- [x] `telemetry = false` is under `[settings]`

### Step 3. Install moon through proto

```bash
proto use
moon --version
```

**Checklist**

- [x] `proto use` finished without errors
- [x] `moon --version` prints `2.5.5`
- [x] `which moon` resolves to `~/.proto/shims/moon`
- [x] `ls ~/.proto/tools/moon` shows a `2.5.5` directory

### Step 4. Create `.moon/workspace.yml`

```yaml
$schema: "https://moonrepo.dev/schemas/workspace.json"

projects:
  - "apps/*"

vcs:
  client: "git"
  defaultBranch: "master"

# Also disables moon's own update check.
telemetry: false
```

**Checklist**

- [x] `.moon/workspace.yml` exists
- [x] `projects` points at `apps/*`
- [x] `telemetry` is `false`
- [ ] `moon query projects` does not complain about `workspace.yml`

### Step 5. Create `.moon/toolchains.yml`

These are the versions moon installs into the proto home and prepends to
`PATH` for every task.

```yaml
$schema: "https://moonrepo.dev/schemas/toolchains.json"

node:
  version: "22.13.0"

pnpm:
  version: "12.2.1"
```

**Checklist**

- [x] `.moon/toolchains.yml` exists (plural, not `toolchain.yml`)
- [x] `node.version` is `22.13.0`
- [x] `pnpm.version` is `12.2.1`
- [x] Both versions are exact, no ranges or aliases

### Step 6. Create the workspace package files

`package.json`:

```json
{
  "name": "moon-demo",
  "private": true,
  "packageManager": "pnpm@12.2.1"
}
```

`pnpm-workspace.yaml`:

```yaml
packages:
  - "apps/*"
```

**Checklist**

- [x] `package.json` exists with `"packageManager": "pnpm@12.2.1"`
- [x] `pnpm-workspace.yaml` exists with `apps/*`
- [x] The pnpm version in `packageManager` matches `.moon/toolchains.yml`

### Step 7. Create one project at `apps/hello`

`apps/hello/package.json`:

```json
{
  "name": "hello",
  "private": true,
  "version": "0.0.0"
}
```

`apps/hello/src/index.js`:

```js
console.log(`hello from node ${process.version}`);
```

`apps/hello/moon.yml`:

```yaml
$schema: "https://moonrepo.dev/schemas/project.json"

language: "javascript"
toolchains:
  default: "node"

tasks:
  build:
    command: "node src/index.js"
    inputs:
      - "src/**/*"
  versions:
    command: 'bash -c "node --version && pnpm --version"'
    options:
      cache: false
```

**Checklist**

- [x] `apps/hello/package.json` exists
- [x] `apps/hello/src/index.js` exists
- [x] `apps/hello/moon.yml` exists with `build` and `versions` tasks
- [x] `moon query projects` lists `hello`
- [x] `moon query tasks` lists `hello:build` and `hello:versions`

### Step 8. Run it locally

```bash
moon setup
moon run hello:build
moon run hello:versions
ls ~/.proto/tools/node ~/.proto/tools/pnpm
```

The `versions` task prints the versions from the toolchain, not from your
shell. Run `hello:build` twice and the second run should report a cache hit.

**Checklist**

- [x] `moon setup` finished without errors
- [x] `moon run hello:build` prints `hello from node v22.13.0`
- [x] Running `moon run hello:build` a second time reports a cache hit
- [x] `moon run hello:versions` prints `v22.13.0` and `12.2.1`
- [x] `ls ~/.proto/tools/node` shows `22.13.0`
- [x] `ls ~/.proto/tools/pnpm` shows `12.2.1`
- [x] A `.moon/cache/` directory was created (add it to `.gitignore`)

## Part 2. The Dockerfile

### Step 9. Create `Dockerfile` at the repo root

The key is that `PROTO_HOME` points at a fixed path outside the work
directory, so the tools survive deleting the copied config.

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git bash unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

ENV PROTO_HOME=/proto \
    PATH=/proto/shims:/proto/bin:$PATH

# Install proto itself, pinned to the version in .prototools.
RUN curl -fsSL https://moonrepo.dev/install/proto.sh | bash -s -- 0.62.3 --yes --no-profile

# The source is mounted at runtime with the host uid; git must accept it.
RUN git config --global --add safe.directory '*'

WORKDIR /work

# Copy only the config that decides tool versions. This layer is reused
# until one of these files changes.
COPY .prototools package.json pnpm-workspace.yaml ./
COPY .moon/ .moon/

# proto use   -> moon (and proto) from .prototools
# moon setup  -> node and pnpm from .moon/toolchains.yml
RUN proto use \
 && moon setup \
 && rm -rf /work/.moon /work/* /work/.prototools \
 && chmod -R a+rwX /proto

CMD ["bash"]
```

**Checklist**

- [ ] `Dockerfile` exists at the repo root
- [ ] `PROTO_HOME=/proto` is set before proto is installed
- [ ] `/proto/shims` and `/proto/bin` are on `PATH`
- [ ] The proto install version matches `.prototools`
- [ ] Only config files are copied, no `apps/` source
- [ ] The `RUN` step ends with `rm -rf` of the copied config and `chmod -R a+rwX /proto`

### Step 10. Build it

```bash
docker build -t moon-demo .
```

**Checklist**

- [ ] `docker build -t moon-demo .` finished without errors
- [ ] The build log shows proto installing `moon`, `node` and `pnpm`
- [ ] `docker image ls moon-demo` shows the image
- [ ] Re-running the build without changing config files reuses the cached toolchain layer

### Step 11. Prove the toolchain is baked

Mount the repo and run with networking disabled. If anything tried to
download, it would fail here.

```bash
docker run --rm --network none \
  -u "$(id -u):$(id -g)" \
  -v "$PWD:/work" -w /work \
  moon-demo moon run hello:versions
```

Expected output is node 22.13.0 and pnpm 12.2.1 printed from inside the
container. Then inspect what was baked:

```bash
docker run --rm moon-demo ls /proto/tools /proto/tools/node /proto/plugins
```

**Checklist**

- [ ] The `--network none` run finishes without errors
- [ ] Output shows `v22.13.0` and `12.2.1`
- [ ] No "downloading" or "installing" messages appear in the output
- [ ] `docker run --rm moon-demo ls /proto/tools` lists `moon`, `node`, `pnpm`, `proto`
- [ ] `docker run --rm moon-demo ls /proto/plugins` is not empty
- [ ] Run with `-u "$(id -u):$(id -g)"` succeeds, so a non-root user can use `/proto`
- [ ] Optional: change `node.version` to `22` and rebuild, confirm the offline run now fails

## What to watch for

- **Exact pins only.** If a pin becomes `22` or `latest`, step 11 fails
  because moon needs the remote version list to resolve it.
- **The `chmod` line** lets a non-root job user write to the proto home.
  Without it, step 11 with `-u` fails on permission errors even though the
  tools are present.
- **Changing a version in the repo** without rebuilding the image makes that
  job download again. That is the trade-off of baking.
- **Project dependencies are not baked.** This demo has none, so
  `pnpm install` is trivial. In a real repo, add a pnpm store volume.
- **Plugins fetched with `github://`** are cached for seven days, after which
  moon re-checks GitHub. Pin them to a release tag or `https://` URL for
  air-gapped runners.

## How moon manages toolchains (background)

- Moon delegates tool installation to proto. Tools live under
  `$PROTO_HOME/tools/<tool>/<version>` (default `~/.proto`).
- Versions come from `.moon/toolchains.yml`, per-project `moon.yml`, and by
  default also `.prototools`.
- When a task runs, moon prepends each toolchain's binary directory to `PATH`.
  Shims are only for interactive shells.
- `MOON_TOOLCHAIN_FORCE_GLOBALS=true` makes moon use whatever is on `PATH`
  instead, for images that pre-install tools by other means.
- Corporate networks: `.prototools` supports `[settings.http]` for proxies and
  root certs, `[settings.url-rewrites]` for mirrors, and `[settings.offline]`
  for connectivity detection hosts.

Sources: <https://moonrepo.dev/docs/concepts/toolchain>,
<https://moonrepo.dev/docs/config/toolchain>, <https://moonrepo.dev/docs/proto>,
<https://moonrepo.dev/docs/proto/config>, <https://moonrepo.dev/docs/guides/ci>,
<https://moonrepo.dev/docs/guides/wasm-plugins>.
