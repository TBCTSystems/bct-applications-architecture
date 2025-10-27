# ECA Web UI - Interactive Certificate Management Dashboard

Modern, production-ready web dashboard for real-time monitoring and management of Edge Certificate Agents (ACME and EST).

## Features

### Real-time Monitoring
- **Live Log Streaming**: Query and display logs from Grafana Loki with auto-refresh
- **Certificate Status**: Real-time certificate lifecycle event tracking
- **Agent Health**: Monitor agent heartbeats and operational status
- **Statistics Dashboard**: Visual overview of log counts, errors, and warnings

### Interactive Controls
- **Agent Management**: Restart ACME/EST agents with one-click buttons
- **Force Operations**: Trigger immediate certificate checks and renewals
- **Toast Notifications**: Visual feedback for all user actions

### Modern UI/UX
- **Dark/Light Theme**: Toggle between themes with persistent localStorage
- **Responsive Design**: Mobile-first design works on all screen sizes
- **Loading States**: Shimmer effects and skeleton screens
- **Search & Filter**: Filter logs by agent, severity, and search terms
- **Export Functionality**: Download logs as JSON for offline analysis

## Technology Stack

### Frontend
- **React 18**: Modern UI framework with hooks
- **Vite**: Lightning-fast build tool and dev server
- **Tailwind CSS**: Utility-first CSS framework
- **Lucide Icons**: Beautiful, consistent icon library
- **date-fns**: Lightweight date formatting

### Backend
- **Node.js 20**: JavaScript runtime
- **Express**: Minimal web framework
- **Axios**: HTTP client for Loki queries
- **Docker CLI**: Agent control via Docker socket

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Web Browser                          │
│  (React App @ http://localhost:8888)                    │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Express Backend (Port 8080)                 │
│  ┌─────────────────────────────────────────────────┐   │
│  │  API Endpoints:                                  │   │
│  │  - GET  /api/health                             │   │
│  │  - GET  /api/logs         (Loki queries)       │   │
│  │  - GET  /api/stats        (Log statistics)     │   │
│  │  - GET  /api/certificates (Cert status)        │   │
│  │  - GET  /api/agents/status (Heartbeats)        │   │
│  │  - POST /api/agent/:type/restart                │   │
│  └─────────────────────────────────────────────────┘   │
└───────┬─────────────────────────────────┬───────────────┘
        │                                 │
        │ Loki HTTP API                   │ Docker Socket
        ▼                                 ▼
┌───────────────────┐         ┌──────────────────────────┐
│  Grafana Loki     │         │  Docker Engine           │
│  (Port 3100)      │         │  - eca-acme-agent        │
│                   │         │  - eca-est-agent         │
└───────────────────┘         └──────────────────────────┘
```

## API Documentation

### Health Check
```http
GET /api/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-10-26T12:00:00.000Z"
}
```

### Query Logs
```http
GET /api/logs?query={agent_type="acme"}&limit=100
```

**Parameters:**
- `query` (string): LogQL query string (default: `{agent_type=~"acme|est"}`)
- `limit` (number): Maximum number of logs to return (default: 100)
- `start` (number): Start time in nanoseconds (default: 1 hour ago)
- `end` (number): End time in nanoseconds (default: now)

**Response:**
```json
{
  "success": true,
  "count": 42,
  "logs": [
    {
      "timestamp": "2025-10-26T12:00:00.000Z",
      "severity": "INFO",
      "message": "Certificate check complete",
      "context": {
        "domain": "target-server",
        "lifetime_elapsed_pct": 45
      },
      "labels": {
        "agent_type": "acme",
        "severity": "INFO"
      }
    }
  ]
}
```

### Get Statistics
```http
GET /api/stats
```

**Response:**
```json
{
  "success": true,
  "stats": {
    "acme_total": 120,
    "est_total": 95,
    "errors": 2,
    "warnings": 8
  },
  "timestamp": "2025-10-26T12:00:00.000Z"
}
```

### Get Certificate Status
```http
GET /api/certificates
```

**Response:**
```json
{
  "success": true,
  "certificates": {
    "acme": {
      "status": "healthy",
      "lastSeen": "2025-10-26T12:00:00.000Z",
      "events": [
        {
          "timestamp": "2025-10-26T11:59:00.000Z",
          "message": "Certificate renewal triggered",
          "severity": "INFO"
        }
      ]
    },
    "est": {
      "status": "warning",
      "lastSeen": "2025-10-26T11:58:00.000Z",
      "events": []
    }
  }
}
```

### Get Agent Status
```http
GET /api/agents/status
```

**Response:**
```json
{
  "success": true,
  "agents": {
    "acme": {
      "status": "healthy",
      "lastHeartbeat": "2025-10-26T12:00:00.000Z",
      "ageSeconds": 5
    },
    "est": {
      "status": "healthy",
      "lastHeartbeat": "2025-10-26T12:00:00.000Z",
      "ageSeconds": 8
    }
  }
}
```

### Restart Agent
```http
POST /api/agent/:type/restart
```

**Parameters:**
- `type` (path): Agent type - either "acme" or "est"

**Response:**
```json
{
  "success": true,
  "message": "Agent acme restarted successfully",
  "container": "eca-acme-agent",
  "timestamp": "2025-10-26T12:00:00.000Z"
}
```

## Setup Instructions

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.x
- Node.js 20+ (for local development only)

### Production Deployment (Docker)

1. **Enable the web-ui service** in docker-compose:
   ```bash
   cd /home/karol/dev/code-tbct/poc
   docker compose --profile optional up -d web-ui
   ```

2. **Verify service is running**:
   ```bash
   docker compose ps web-ui
   docker compose logs -f web-ui
   ```

3. **Access the dashboard**:
   Open your browser to http://localhost:8888

4. **Stop the service**:
   ```bash
   docker compose stop web-ui
   ```

### Local Development

1. **Install dependencies**:
   ```bash
   cd web-ui
   npm install
   ```

2. **Start development servers**:
   ```bash
   # Terminal 1: Start backend server
   npm run server

   # Terminal 2: Start Vite dev server
   npm run client
   ```

3. **Access development environment**:
   - Frontend: http://localhost:3000 (Vite dev server with HMR)
   - Backend: http://localhost:8080 (Express API)

4. **Build for production**:
   ```bash
   npm run build
   ```
   Output will be in `dist/` directory.

### Environment Variables

The web-ui service supports the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `LOKI_URL` | `http://loki:3100` | Grafana Loki API endpoint |
| `NODE_ENV` | `production` | Node environment (production/development) |
| `PORT` | `8080` | Internal server port |
| `SERVER_CERT_PATH` | `/certs/server` | Path to ACME certificates |
| `CLIENT_CERT_PATH` | `/certs/client` | Path to EST certificates |

## Usage Guide

### Dashboard Overview

The dashboard is divided into several sections:

1. **Statistics Cards** (Top)
   - ACME Logs: Total ACME agent log entries in the last hour
   - EST Logs: Total EST agent log entries in the last hour
   - Warnings: Count of WARN-level logs
   - Errors: Count of ERROR-level logs

2. **Agent Status Cards**
   - Visual health indicators (green=healthy, yellow=warning, red=error)
   - Last heartbeat timestamp
   - Age of last log entry in seconds

3. **Certificate Status**
   - Real-time certificate lifecycle events
   - Recent events for both ACME and EST certificates
   - Status badges showing certificate health

4. **Agent Controls**
   - Interactive buttons to restart agents
   - Toast notifications for action feedback
   - Warning notes about restart behavior

5. **Log Stream**
   - Real-time log viewer with auto-refresh
   - Filter by agent type (all, acme, est, errors, warnings)
   - Search functionality for finding specific logs
   - Export logs as JSON

### Common Tasks

#### View ACME Agent Logs
1. Navigate to the Log Stream section
2. Click the "acme" filter button
3. Logs are automatically refreshed every 5 seconds

#### Force Certificate Renewal
1. Scroll to the Agent Controls section
2. Click "Force Renewal" for the ACME agent
3. Watch for success notification
4. Monitor the Log Stream for renewal events

#### Export Error Logs
1. In Log Stream section, click "errors" filter
2. Optionally search for specific error text
3. Click the "Export" button
4. JSON file will download automatically

#### Monitor Certificate Health
1. Check the Certificate Status section
2. Green badge = healthy, yellow = warning, red = error
3. Expand "Recent Events" to see detailed timeline
4. Last seen timestamp shows latest activity

#### Toggle Dark Mode
1. Click the moon/sun icon in the header
2. Theme preference is saved to localStorage
3. Persists across browser sessions

## Troubleshooting

### Web UI Not Accessible

**Problem**: Cannot access http://localhost:8888

**Solutions**:
1. Verify the service is running:
   ```bash
   docker compose --profile optional ps web-ui
   ```

2. Check service logs:
   ```bash
   docker compose --profile optional logs web-ui
   ```

3. Verify port is not in use:
   ```bash
   netstat -an | grep 8888
   ```

### No Logs Displayed

**Problem**: Log Stream shows "No logs found"

**Solutions**:
1. Verify Loki is running:
   ```bash
   docker compose ps loki
   curl http://localhost:3100/ready
   ```

2. Verify agents are running and emitting logs:
   ```bash
   docker compose ps eca-acme-agent eca-est-agent
   docker compose logs --tail=20 eca-acme-agent
   ```

3. Check FluentD is forwarding logs:
   ```bash
   docker compose ps fluentd
   curl http://localhost:24220/api/plugins.json
   ```

### Agent Restart Button Not Working

**Problem**: Clicking "Force Renewal" shows error

**Solutions**:
1. Verify Docker socket is mounted:
   ```bash
   docker compose exec web-ui ls -la /var/run/docker.sock
   ```

2. Check web-ui has permissions:
   ```bash
   docker compose exec web-ui docker ps
   ```

3. View backend server logs:
   ```bash
   docker compose logs web-ui | grep -i error
   ```

### Backend Connection Failed

**Problem**: Dashboard shows "Offline" status

**Solutions**:
1. Check backend health endpoint:
   ```bash
   curl http://localhost:8888/api/health
   ```

2. Verify network connectivity:
   ```bash
   docker compose exec web-ui ping loki
   ```

3. Check LOKI_URL environment variable:
   ```bash
   docker compose exec web-ui env | grep LOKI_URL
   ```

## Performance Considerations

### Auto-refresh Interval
- Default: 5 seconds
- Recommended for production: 10-30 seconds
- Can be changed in the dashboard controls

### Log Query Limits
- Default: 50 logs per query
- Maximum: 200 logs per query
- Higher limits increase load on Loki

### Browser Performance
- Log Stream uses virtualization for large datasets
- Old logs are automatically pruned
- Clear browser cache if experiencing slowdowns

## Security Considerations

### Docker Socket Access
- Web UI requires Docker socket access for agent control
- Socket is mounted read-only in docker-compose.yml
- Only allows restarting specific containers

### Sensitive Data
- Logs may contain certificate details
- Private keys are never exposed in logs
- Use HTTPS in production deployments

### Authentication
- Web UI currently has no built-in authentication
- Intended for internal/demo use only
- Add reverse proxy with auth for production

## Development

### Project Structure
```
web-ui/
├── server/
│   └── index.js              # Express backend server
├── src/
│   ├── components/           # React components
│   │   ├── Dashboard.jsx     # Main dashboard container
│   │   ├── Header.jsx        # App header with theme toggle
│   │   ├── StatsCards.jsx    # Statistics overview cards
│   │   ├── AgentStatus.jsx   # Agent health cards
│   │   ├── CertificateStatus.jsx # Certificate status cards
│   │   ├── AgentControls.jsx # Agent restart controls
│   │   └── LogStream.jsx     # Real-time log viewer
│   ├── context/
│   │   └── ThemeContext.jsx  # Theme management context
│   ├── App.jsx               # Root application component
│   ├── main.jsx              # React entry point
│   └── index.css             # Global styles + Tailwind
├── public/
│   └── favicon.svg           # App icon
├── Dockerfile                # Multi-stage production build
├── package.json              # Dependencies and scripts
├── vite.config.js            # Vite configuration
├── tailwind.config.js        # Tailwind CSS configuration
├── postcss.config.js         # PostCSS configuration
└── README.md                 # This file
```

### Adding New Features

1. **New API Endpoint**: Add route in `server/index.js`
2. **New Component**: Create in `src/components/`
3. **New Style**: Add to `src/index.css` or component file
4. **New Dependency**: `npm install <package>` and rebuild Docker image

### Testing Changes

1. Make code changes
2. Test locally with `npm run dev`
3. Rebuild Docker image: `docker compose build web-ui`
4. Restart service: `docker compose --profile optional up -d web-ui`
5. View logs: `docker compose logs -f web-ui`

## Contributing

When contributing to the Web UI:

1. Follow React best practices and hooks patterns
2. Use Tailwind utility classes for styling
3. Add proper error handling and loading states
4. Test responsive design on mobile/tablet/desktop
5. Update this README with new features

## License

Part of the Edge Certificate Agent (ECA) Proof of Concept project.

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review Docker Compose logs
3. Consult the main ECA PoC documentation
4. Check Grafana dashboards at http://localhost:3000

## Changelog

### Version 1.0.0 (2025-10-26)
- Initial release
- Real-time log streaming from Loki
- Agent health monitoring
- Certificate status tracking
- Interactive agent controls
- Dark/light theme support
- Responsive mobile design
- Export logs functionality
