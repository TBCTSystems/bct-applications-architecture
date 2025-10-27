# Web UI Testing Instructions

This document provides step-by-step instructions for testing the ECA Web UI.

## Pre-requisites

Before testing the Web UI, ensure the following services are running:

```bash
cd /home/karol/dev/code-tbct/poc

# Start the core observability stack
docker compose up -d fluentd loki grafana

# Start the PKI and agents
docker compose up -d pki eca-acme-agent eca-est-agent

# Wait for services to be healthy (30-60 seconds)
docker compose ps
```

Expected output should show all services as "healthy" or "running".

## Testing Steps

### Step 1: Build and Start the Web UI

```bash
# Build the web-ui Docker image
docker compose --profile optional build web-ui

# Start the web-ui service
docker compose --profile optional up -d web-ui

# Check if the service started successfully
docker compose --profile optional ps web-ui
```

Expected output:
```
NAME         IMAGE              STATUS         PORTS
eca-web-ui   poc-web-ui         Up (healthy)   0.0.0.0:8888->8080/tcp
```

### Step 2: Verify Backend Health

```bash
# Check backend health endpoint
curl http://localhost:8888/api/health

# Expected response:
# {"status":"healthy","timestamp":"2025-10-26T..."}
```

### Step 3: Test Loki Connectivity

```bash
# Test Loki query endpoint
curl http://localhost:8888/api/logs?limit=10

# Should return JSON with logs array
```

### Step 4: Access the Web Dashboard

1. Open your browser to: **http://localhost:8888**
2. You should see the ECA Dashboard with:
   - Header with "ECA Dashboard" title
   - Theme toggle button (moon/sun icon)
   - Connection status indicator (green dot)
   - Statistics cards showing log counts
   - Agent status cards (ACME and EST)
   - Certificate status section
   - Agent controls with restart buttons
   - Log stream section

### Step 5: Test Real-time Features

1. **Auto-refresh**:
   - Verify "Auto-refresh" checkbox is enabled by default
   - Watch the statistics update every 5 seconds
   - Change refresh interval to 10s or 30s

2. **Manual Refresh**:
   - Click the "Refresh" button in the top-right
   - All data should update immediately

3. **Theme Toggle**:
   - Click the moon/sun icon in the header
   - Dashboard should switch between light and dark themes
   - Refresh the page - theme should persist

### Step 6: Test Log Streaming

1. **View All Logs**:
   - Scroll to the "Log Stream" section
   - Should display recent logs from both ACME and EST agents
   - Logs should auto-refresh every 5 seconds

2. **Filter Logs**:
   - Click "acme" filter - should show only ACME logs
   - Click "est" filter - should show only EST logs
   - Click "errors" filter - should show only ERROR severity logs
   - Click "warnings" filter - should show only WARN severity logs
   - Click "all" to reset filter

3. **Search Logs**:
   - Type "certificate" in the search box
   - Log list should filter to show only matching entries
   - Clear search box to see all logs again

4. **Export Logs**:
   - Click the "Export" button
   - A JSON file should download with current logs

5. **Change Limit**:
   - Select "100 logs" from the dropdown
   - More logs should appear

### Step 7: Test Agent Controls

1. **Restart ACME Agent**:
   ```bash
   # In the browser:
   # 1. Scroll to "Agent Controls" section
   # 2. Click "Force Renewal" button under ACME Agent
   # 3. Watch for green success notification
   # 4. Verify in terminal:
   docker compose logs --tail=20 eca-acme-agent
   ```

   You should see the agent container restart and emit new logs.

2. **Restart EST Agent**:
   ```bash
   # In the browser:
   # 1. Click "Force Enrollment" button under EST Agent
   # 2. Watch for green success notification
   # 3. Verify in terminal:
   docker compose logs --tail=20 eca-est-agent
   ```

### Step 8: Test Certificate Status

1. **View Certificate Cards**:
   - Check the "Certificate Status" section
   - Should show status for both ACME and EST certificates
   - Status badges should be: Healthy (green), Warning (yellow), or Error (red)

2. **View Recent Events**:
   - Each certificate card shows recent events
   - Events should include timestamps and severity levels
   - Color coding: ERROR=red, WARN=yellow, INFO=blue

### Step 9: Test Agent Health

1. **Agent Status Cards**:
   - Top section shows ACME Agent and EST Agent status cards
   - Green pulsing dot = healthy
   - Yellow dot = warning (logs older than 2 minutes)
   - Red dot = stale/error (logs older than 5 minutes)

2. **Last Heartbeat**:
   - Each card shows "Last heartbeat: X seconds ago"
   - Should update every 5 seconds

### Step 10: Test Responsive Design

1. **Desktop View** (1920x1080):
   - All cards should be in a grid layout
   - No horizontal scrolling
   - All buttons and controls visible

2. **Tablet View** (768x1024):
   - Resize browser window to ~768px wide
   - Cards should stack vertically
   - Navigation should remain functional

3. **Mobile View** (375x667):
   - Resize to mobile size
   - All content should be readable
   - No elements cut off
   - Buttons should be tappable

### Step 11: Test Error Handling

1. **Stop Loki**:
   ```bash
   docker compose stop loki
   ```
   - Refresh the dashboard
   - Should show error messages in red boxes
   - Backend status should show "Offline"

2. **Restart Loki**:
   ```bash
   docker compose start loki
   ```
   - Wait 10 seconds for health check
   - Dashboard should recover automatically
   - Status should show "Connected"

### Step 12: View Backend Logs

```bash
# View real-time backend logs
docker compose logs -f web-ui

# Should show:
# - Server startup message
# - API requests
# - Loki queries
# - Docker restart commands
```

## Expected Results

### Successful Deployment Checklist

- [ ] Web UI container is running and healthy
- [ ] Dashboard accessible at http://localhost:8888
- [ ] Statistics cards show non-zero values
- [ ] Agent status cards show "Healthy" with green indicators
- [ ] Certificate status shows recent events
- [ ] Log stream displays logs and auto-refreshes
- [ ] Theme toggle works and persists
- [ ] ACME agent restart button works
- [ ] EST agent restart button works
- [ ] Export logs button downloads JSON file
- [ ] Search and filter functionality works
- [ ] Responsive design works on mobile/tablet/desktop
- [ ] No errors in browser console
- [ ] No errors in backend logs

### Performance Benchmarks

- Initial page load: < 2 seconds
- Log query response: < 500ms
- Statistics update: < 300ms
- Theme toggle: Instant
- Agent restart: < 5 seconds

## Troubleshooting Common Issues

### Issue: Port 8888 already in use

**Solution**:
```bash
# Find process using port 8888
netstat -tulpn | grep 8888

# Or change port in docker-compose.yml
# ports:
#   - "9999:8080"  # Use port 9999 instead
```

### Issue: Web UI shows "Offline"

**Solution**:
```bash
# Check Loki is running
docker compose ps loki

# Check Loki health
curl http://localhost:3100/ready

# Check web-ui can reach Loki
docker compose exec web-ui ping loki
```

### Issue: No logs displayed

**Solution**:
```bash
# Verify agents are running
docker compose ps eca-acme-agent eca-est-agent

# Verify agents are logging
docker compose logs --tail=50 eca-acme-agent

# Check FluentD
docker compose ps fluentd
docker compose logs fluentd | grep -i error
```

### Issue: Restart buttons don't work

**Solution**:
```bash
# Verify Docker socket is mounted
docker compose exec web-ui ls -la /var/run/docker.sock

# Test Docker access
docker compose exec web-ui docker ps

# Check backend logs
docker compose logs web-ui | grep -i restart
```

### Issue: Build fails

**Solution**:
```bash
# Clean up old images
docker compose --profile optional down
docker image rm poc-web-ui

# Rebuild from scratch
docker compose --profile optional build --no-cache web-ui
```

## Testing Checklist Summary

```
Web UI Testing Checklist
========================

Pre-requisites:
 [ ] Docker Compose installed
 [ ] Core services running (Loki, agents)
 [ ] Port 8888 available

Build & Deploy:
 [ ] Docker image builds successfully
 [ ] Container starts and reaches healthy state
 [ ] Health endpoint returns 200 OK
 [ ] Dashboard loads in browser

Core Features:
 [ ] Statistics cards display data
 [ ] Agent status cards show health
 [ ] Certificate status shows events
 [ ] Log stream displays logs
 [ ] Auto-refresh works (5s interval)
 [ ] Manual refresh button works

Interactive Controls:
 [ ] Theme toggle works (light/dark)
 [ ] ACME restart button works
 [ ] EST restart button works
 [ ] Toast notifications appear
 [ ] No console errors

Log Stream Features:
 [ ] Filter by agent (acme/est)
 [ ] Filter by severity (errors/warnings)
 [ ] Search functionality works
 [ ] Export logs downloads JSON
 [ ] Limit selector changes count

Responsive Design:
 [ ] Desktop layout correct
 [ ] Tablet layout correct
 [ ] Mobile layout correct
 [ ] No horizontal scroll
 [ ] All buttons accessible

Error Handling:
 [ ] Shows error when Loki down
 [ ] Recovers when Loki restored
 [ ] Shows loading states
 [ ] Handles network timeouts

Performance:
 [ ] Page loads < 2 seconds
 [ ] Queries respond < 500ms
 [ ] No memory leaks
 [ ] No excessive API calls

Clean Up:
 [ ] Stop services: docker compose --profile optional stop web-ui
 [ ] Remove container: docker compose --profile optional down web-ui
```

## Next Steps

After successful testing:

1. **Document any issues** found during testing
2. **Take screenshots** of the dashboard for documentation
3. **Monitor resource usage** (docker stats eca-web-ui)
4. **Test with production-like data** (longer time periods)
5. **Consider adding authentication** for production use

## Support

If you encounter issues not covered in this guide:

1. Check the main README.md for API documentation
2. Review docker-compose logs for all services
3. Test Loki queries directly with curl
4. Verify network connectivity between containers
5. Check browser developer console for JavaScript errors
