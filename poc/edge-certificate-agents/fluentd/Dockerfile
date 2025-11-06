# FluentD Docker Image for ECA Log Aggregation
# Includes Grafana Loki output plugin

FROM fluent/fluentd:v1.16-debian-1

# Switch to root for plugin installation
USER root

# Install required plugins
RUN fluent-gem install fluent-plugin-grafana-loki \
    && fluent-gem install fluent-plugin-rewrite-tag-filter \
    && fluent-gem install fluent-plugin-record-modifier

# Create buffer directory
RUN mkdir -p /var/log/fluentd/buffer && \
    chown -R fluent:fluent /var/log/fluentd

# Switch back to fluent user
USER fluent

# FluentD will use /fluentd/etc/fluent.conf by default
