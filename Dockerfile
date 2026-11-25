FROM debian:bookworm-slim

# Static-analysis + PCAP-forensics toolbox for studying Windows stealer
# captures (e.g. Lumma) WITHOUT executing the sample.
#
# Deliberately contains NO interpreter/loader for the sample itself.
# This image is for INSPECTION ONLY. It must be run with `--network none`.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        file \
        binutils \
        xxd \
        yara \
        radare2 \
        tshark \
        clamav \
        clamav-freshclam \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Python static-analysis tooling in an isolated venv
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir \
        pefile \
        flare-capa \
        yara-python

# Bake ClamAV signatures into the image so scanning works offline
# (container is run with no network). This makes the image larger but
# self-contained. Tolerate partial failures so the build still succeeds.
RUN freshclam || true

# Non-root analyst user; samples are mounted read-only anyway
RUN useradd -m -u 10001 analyst \
    && mkdir -p /samples /output /rules \
    && chown -R analyst:analyst /output /rules

COPY analyze.sh /usr/local/bin/analyze.sh
RUN chmod +x /usr/local/bin/analyze.sh

USER analyst
WORKDIR /work

ENTRYPOINT ["/usr/local/bin/analyze.sh"]
