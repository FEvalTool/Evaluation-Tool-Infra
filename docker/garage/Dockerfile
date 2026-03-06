FROM alpine:3.19

# Download and install Garage v2.2.0 for amd64
RUN wget https://garagehq.deuxfleurs.fr/_releases/v2.2.0/x86_64-unknown-linux-musl/garage -O /usr/local/bin/garage \
    && chmod +x /usr/local/bin/garage

RUN mkdir -p /var/lib/garage/meta /var/lib/garage/data

# Copy init script
COPY scripts/garage/init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE 3900 3901 3902

# Start garage server and run init script
CMD ["/bin/sh", "-c", "garage -c /etc/garage.toml server & sleep 10 && /init.sh && wait"]