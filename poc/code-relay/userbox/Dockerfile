FROM ghcr.io/getpaseo/paseo@sha256:5518da7cdd35f132e8a944c35e509c677a90a8f3ec8a78df98f7fb5fd5e2c6c3

# The agent CLI the daemon manages, pinned to the host's working version.
# Installed with HOME=/root: opencode's postinstall otherwise seeds
# root-owned dirs under the image's $HOME (/home/paseo), which the paseo
# user then cannot write into.
RUN HOME=/root npm install -g --no-audit --no-fund opencode-ai@1.18.31 \
    && npm cache clean --force

# A small git repo for the agent to work in (the diff step needs history).
USER root
RUN mkdir -p /workspace/demo \
    && printf 'demo repo for the relay PoC\n' > /workspace/demo/README.md \
    && git -C /workspace/demo init -q \
    && git -C /workspace/demo config user.email poc@example.invalid \
    && git -C /workspace/demo config user.name "Relay PoC" \
    && git -C /workspace/demo add -A \
    && git -C /workspace/demo commit -qm "seed" \
    && chown -R paseo:paseo /workspace/demo
USER paseo

COPY userbox-entrypoint.sh /usr/local/bin/userbox-entrypoint
USER root
RUN chmod +x /usr/local/bin/userbox-entrypoint \
    && chown -R paseo:paseo /home/paseo
USER paseo

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/userbox-entrypoint"]
