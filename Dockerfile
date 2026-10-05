FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git bash unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Fixed homes for proto and moon, outside any user's $HOME, so the job user
# (which has no home directory) finds the baked tools and plugins.
#   /proto        proto tools and proto plugins
#   /moon         moon toolchain plugins (default ~/.moon)
#   /moon/cache   wasmtime compilation cache (default ~/.cache/wasmtime)
ENV PROTO_HOME=/proto \
    MOON_HOME=/moon
# Separate ENV on purpose: within one ENV instruction, $VAR refers to the
# value before that instruction, so these must come after the line above.
ENV XDG_CACHE_HOME=$MOON_HOME/cache \
    PATH=$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH

# Install proto itself, pinned to the version in .prototools.
RUN curl -fsSL https://moonrepo.dev/install/proto.sh | bash -s -- 0.62.3 --yes --no-profile

# The source is mounted at runtime, possibly owned by another uid; git must
# accept it. --system writes /etc/gitconfig, which every user reads.
# --global would write /root/.gitconfig, invisible to the job user.
RUN git config --system --add safe.directory '*'

WORKDIR /work

# Copy only the config that decides tool versions. This layer is reused
# until one of these files changes. package.json is not needed here because
# node and pnpm versions come from .moon/toolchains.yml, and this image does
# not install project dependencies.
COPY .prototools ./
COPY .moon/ .moon/

# proto use   -> moon (and proto) from .prototools
# moon setup  -> node and pnpm from .moon/toolchains.yml
RUN proto use \
 && moon setup \
 && rm -rf /work/.moon /work/.prototools \
 && chmod -R a+rwX "$PROTO_HOME" "$MOON_HOME"

CMD ["bash"]