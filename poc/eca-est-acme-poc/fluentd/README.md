# FluentD Configuration for ECA

This directory contains FluentD configuration for log aggregation.

## Files

- **Dockerfile**: FluentD container image with Loki output plugin
- **fluent.conf**: FluentD configuration (input, filters, output)

## Configuration Overview

### Input
- FluentD forward protocol on port 24224
- Receives logs from Docker logging driver

### Filters
- Parse JSON log format from ECA agents
- Add container metadata (agent_type, environment)
- Route logs by severity and content

### Output
- Send all logs to Grafana Loki (http://loki:3100)
- Labels: agent_type, severity, environment
- Buffer to file for reliability

## Monitoring

FluentD exposes metrics on port 24220:

```bash
curl http://localhost:24220/api/plugins.json | jq
```

## Customization

### Change Log Retention

Edit `fluent.conf` buffer settings:

```ruby
<buffer>
  flush_interval 5s       # How often to flush to Loki
  chunk_limit_size 1m     # Max buffer chunk size
  retry_max_times 5       # Max retries on failure
</buffer>
```

### Add Additional Outputs

To send logs to multiple backends (e.g., S3, Elasticsearch):

```ruby
<match eca.**>
  @type copy

  # Loki (existing)
  <store>
    @type loki
    url http://loki:3100
    ...
  </store>

  # S3 (new)
  <store>
    @type s3
    s3_bucket my-bucket
    s3_region us-east-1
    ...
  </store>
</match>
```

## Troubleshooting

### View FluentD Logs
```bash
docker logs eca-fluentd
```

### Check Buffer Size
```bash
docker exec eca-fluentd du -sh /var/log/fluentd/buffer
```

### Test Configuration
```bash
# Validate configuration syntax
docker exec eca-fluentd fluentd --dry-run -c /fluentd/etc/fluent.conf
```

## References

- [FluentD Documentation](https://docs.fluentd.org/)
- [FluentD Loki Plugin](https://grafana.com/docs/loki/latest/clients/fluentd/)
