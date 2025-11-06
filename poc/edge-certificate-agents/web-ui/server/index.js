import express from 'express';
import cors from 'cors';
import axios from 'axios';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import { fileURLToPath } from 'url';

const execAsync = promisify(exec);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 8080;
const LOKI_URL = process.env.LOKI_URL || 'http://loki:3100';

app.use(cors());
app.use(express.json());

// Serve static files from the dist directory (production) or public directory (dev)
const staticPath = process.env.NODE_ENV === 'production'
  ? path.join(__dirname, '../dist')
  : path.join(__dirname, '../public');
app.use(express.static(staticPath));

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Query Loki logs
app.get('/api/logs', async (req, res) => {
  try {
    const {
      query = '{agent_type=~"acme|est"}',
      limit = 100,
      start,
      end
    } = req.query;

    // Default time range: last 1 hour
    const endTime = end || Date.now() * 1000000; // nanoseconds
    const startTime = start || (Date.now() - 3600000) * 1000000; // 1 hour ago

    const lokiQuery = {
      query,
      limit: parseInt(limit),
      start: startTime,
      end: endTime,
      direction: 'backward'
    };

    const response = await axios.get(`${LOKI_URL}/loki/api/v1/query_range`, {
      params: lokiQuery,
      timeout: 5000
    });

    // Parse Loki response and extract log entries
    const streams = response.data?.data?.result || [];
    const logs = [];

    streams.forEach(stream => {
      const labels = stream.stream || {};
      const values = stream.values || [];

      values.forEach(([timestamp, logLine]) => {
        try {
          // Try to parse JSON log line
          const parsed = JSON.parse(logLine);
          logs.push({
            timestamp: new Date(parseInt(timestamp) / 1000000).toISOString(),
            ...parsed,
            labels
          });
        } catch (e) {
          // If not JSON, store as plain text
          logs.push({
            timestamp: new Date(parseInt(timestamp) / 1000000).toISOString(),
            message: logLine,
            labels
          });
        }
      });
    });

    // Sort by timestamp descending
    logs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    res.json({
      success: true,
      count: logs.length,
      logs: logs.slice(0, parseInt(limit))
    });
  } catch (error) {
    console.error('Loki query error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message,
      details: error.response?.data || null
    });
  }
});

// Get log statistics
app.get('/api/stats', async (req, res) => {
  try {
    const now = Date.now() * 1000000;
    const oneHourAgo = (Date.now() - 3600000) * 1000000;

    // Query for different metrics
    const queries = {
      acme_total: '{agent_type="acme"}',
      est_total: '{agent_type="est"}',
      errors: '{severity="ERROR"}',
      warnings: '{severity="WARN"}',
    };

    const results = {};

    // Execute all queries in parallel
    await Promise.all(
      Object.entries(queries).map(async ([key, query]) => {
        try {
          const response = await axios.get(`${LOKI_URL}/loki/api/v1/query_range`, {
            params: {
              query,
              limit: 1000,
              start: oneHourAgo,
              end: now
            },
            timeout: 5000
          });

          const streams = response.data?.data?.result || [];
          let count = 0;
          streams.forEach(stream => {
            count += (stream.values || []).length;
          });

          results[key] = count;
        } catch (error) {
          console.error(`Query error for ${key}:`, error.message);
          results[key] = 0;
        }
      })
    );

    res.json({
      success: true,
      stats: results,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Stats error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get certificate status
app.get('/api/certificates', async (req, res) => {
  try {
    // Query recent certificate-related logs
    const now = Date.now() * 1000000;
    const fiveMinutesAgo = (Date.now() - 300000) * 1000000;

    const queries = {
      acme: '{agent_type="acme"} |~ "certificate|cert"',
      est: '{agent_type="est"} |~ "certificate|cert"'
    };

    const certificates = {
      acme: { status: 'unknown', lastSeen: null, events: [] },
      est: { status: 'unknown', lastSeen: null, events: [] }
    };

    await Promise.all(
      Object.entries(queries).map(async ([type, query]) => {
        try {
          const response = await axios.get(`${LOKI_URL}/loki/api/v1/query_range`, {
            params: {
              query,
              limit: 50,
              start: fiveMinutesAgo,
              end: now,
              direction: 'backward'
            },
            timeout: 5000
          });

          const streams = response.data?.data?.result || [];
          const events = [];
          let lastTimestamp = null;

          streams.forEach(stream => {
            (stream.values || []).forEach(([timestamp, logLine]) => {
              try {
                const parsed = JSON.parse(logLine);
                events.push({
                  timestamp: new Date(parseInt(timestamp) / 1000000).toISOString(),
                  message: parsed.message,
                  severity: parsed.severity
                });

                if (!lastTimestamp || parseInt(timestamp) > lastTimestamp) {
                  lastTimestamp = parseInt(timestamp);
                }
              } catch (e) {
                // Skip non-JSON logs
              }
            });
          });

          // Determine status based on recent activity
          if (events.length > 0) {
            const hasErrors = events.some(e => e.severity === 'ERROR');
            const hasWarnings = events.some(e => e.severity === 'WARN');

            certificates[type].status = hasErrors ? 'error' : hasWarnings ? 'warning' : 'healthy';
            certificates[type].lastSeen = lastTimestamp ? new Date(lastTimestamp / 1000000).toISOString() : null;
            certificates[type].events = events.slice(0, 10);
          } else {
            certificates[type].status = 'no-data';
          }
        } catch (error) {
          console.error(`Certificate query error for ${type}:`, error.message);
          certificates[type].status = 'error';
          certificates[type].error = error.message;
        }
      })
    );

    res.json({
      success: true,
      certificates,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Certificate status error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Agent control endpoints
app.post('/api/agent/:type/restart', async (req, res) => {
  try {
    const { type } = req.params;

    if (!['acme', 'est'].includes(type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid agent type. Must be "acme" or "est"'
      });
    }

    const containerName = `eca-${type}-agent`;

    console.log(`Restarting agent: ${containerName}`);

    // Execute docker restart command
    const { stdout, stderr } = await execAsync(`docker restart ${containerName}`);

    res.json({
      success: true,
      message: `Agent ${type} restarted successfully`,
      container: containerName,
      output: stdout,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Agent restart error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message,
      stderr: error.stderr
    });
  }
});

// Get agent heartbeat status
app.get('/api/agents/status', async (req, res) => {
  try {
    const now = Date.now() * 1000000;
    const fiveMinutesAgo = (Date.now() - 300000) * 1000000;

    const agents = {
      acme: { status: 'unknown', lastHeartbeat: null },
      est: { status: 'unknown', lastHeartbeat: null }
    };

    await Promise.all(
      ['acme', 'est'].map(async (type) => {
        try {
          const response = await axios.get(`${LOKI_URL}/loki/api/v1/query_range`, {
            params: {
              query: `{agent_type="${type}"}`,
              limit: 10,
              start: fiveMinutesAgo,
              end: now,
              direction: 'backward'
            },
            timeout: 5000
          });

          const streams = response.data?.data?.result || [];
          let latestTimestamp = null;

          streams.forEach(stream => {
            (stream.values || []).forEach(([timestamp]) => {
              const ts = parseInt(timestamp);
              if (!latestTimestamp || ts > latestTimestamp) {
                latestTimestamp = ts;
              }
            });
          });

          if (latestTimestamp) {
            const lastHeartbeat = new Date(latestTimestamp / 1000000);
            const ageSeconds = (Date.now() - lastHeartbeat.getTime()) / 1000;

            agents[type].lastHeartbeat = lastHeartbeat.toISOString();
            agents[type].ageSeconds = Math.floor(ageSeconds);

            // Determine status based on age
            if (ageSeconds < 120) {
              agents[type].status = 'healthy';
            } else if (ageSeconds < 300) {
              agents[type].status = 'warning';
            } else {
              agents[type].status = 'stale';
            }
          } else {
            agents[type].status = 'no-data';
          }
        } catch (error) {
          console.error(`Agent status error for ${type}:`, error.message);
          agents[type].status = 'error';
          agents[type].error = error.message;
        }
      })
    );

    res.json({
      success: true,
      agents,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Agent status error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Fallback route for SPA
app.get('*', (req, res) => {
  const indexPath = process.env.NODE_ENV === 'production'
    ? path.join(__dirname, '../dist/index.html')
    : path.join(__dirname, '../public/index.html');
  res.sendFile(indexPath);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`ECA Web UI server listening on port ${PORT}`);
  console.log(`Loki URL: ${LOKI_URL}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
