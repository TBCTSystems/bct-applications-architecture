import React, { useState, useEffect } from 'react';
import {
  Container,
  Grid,
  Paper,
  Typography,
  Box,
  Alert,
  CircularProgress,
  Chip,
  Card,
  CardContent,
} from '@mui/material';
import { useSignalR } from '../hooks/useSignalR';
import { ApiService } from '../services/apiService';
import { DeviceSummary, CentrifugeTelemetryData } from '../types/telemetry';
import DeviceCard from './DeviceCard';
import TelemetryChart from './TelemetryChart';

const Dashboard: React.FC = () => {
  const [devices, setDevices] = useState<DeviceSummary[]>([]);
  const [selectedDevice, setSelectedDevice] = useState<string | null>(null);
  const [telemetryHistory, setTelemetryHistory] = useState<CentrifugeTelemetryData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const {
    isConnected,
    isConnecting,
    error: signalRError,
    latestTelemetry,
    latestStatus,
    latestAlert,
    mqttConnectionStatus,
    joinAllDevicesGroup,
    joinDeviceGroup,
  } = useSignalR();

  // Load initial data
  useEffect(() => {
    const loadDevices = async () => {
      try {
        setLoading(true);
        const devicesData = await ApiService.getDevices();
        setDevices(devicesData);
        
        // Select first device by default
        if (devicesData.length > 0 && !selectedDevice) {
          setSelectedDevice(devicesData[0].deviceId);
        }
        
        setError(null);
      } catch (err) {
        console.error('Failed to load devices:', err);
        setError('Failed to load devices');
      } finally {
        setLoading(false);
      }
    };

    loadDevices();
  }, [selectedDevice]);

  // Load telemetry history for selected device
  useEffect(() => {
    const loadTelemetryHistory = async () => {
      if (!selectedDevice) return;

      try {
        const history = await ApiService.getTelemetryHistory(selectedDevice, { limit: 50 });
        setTelemetryHistory(history);
      } catch (err) {
        console.error('Failed to load telemetry history:', err);
      }
    };

    loadTelemetryHistory();
  }, [selectedDevice]);

  // Join SignalR groups when connected
  useEffect(() => {
    if (isConnected) {
      joinAllDevicesGroup();
      if (selectedDevice) {
        joinDeviceGroup(selectedDevice);
      }
    }
  }, [isConnected, selectedDevice, joinAllDevicesGroup, joinDeviceGroup]);

  // Update devices when receiving real-time data
  useEffect(() => {
    if (latestTelemetry) {
      setDevices(prev => prev.map(device => 
        device.deviceId === latestTelemetry.deviceId
          ? { ...device, latestTelemetry, lastSeen: latestTelemetry.timestamp, isConnected: true }
          : device
      ));

      // Add to history if it's for the selected device
      if (latestTelemetry.deviceId === selectedDevice) {
        setTelemetryHistory(prev => {
          const newHistory = [...prev, latestTelemetry];
          // Keep only last 50 records
          return newHistory.slice(-50);
        });
      }
    }
  }, [latestTelemetry, selectedDevice]);

  // Update devices when receiving status updates
  useEffect(() => {
    if (latestStatus) {
      setDevices(prev => prev.map(device => 
        device.deviceId === latestStatus.deviceId
          ? { ...device, latestStatus, lastSeen: latestStatus.timestamp, isConnected: true }
          : device
      ));
    }
  }, [latestStatus]);

  // Update devices when receiving alerts
  useEffect(() => {
    if (latestAlert) {
      setDevices(prev => prev.map(device => 
        device.deviceId === latestAlert.deviceId
          ? { 
              ...device, 
              recentAlerts: [...device.recentAlerts.slice(-9), latestAlert],
              lastSeen: latestAlert.timestamp,
              isConnected: true
            }
          : device
      ));
    }
  }, [latestAlert]);

  const selectedDeviceData = devices.find(d => d.deviceId === selectedDevice);

  if (loading) {
    return (
      <Container maxWidth="lg" sx={{ mt: 4, display: 'flex', justifyContent: 'center' }}>
        <CircularProgress />
      </Container>
    );
  }

  return (
    <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
      {/* Header */}
      <Box mb={4}>
        <Typography variant="h4" component="h1" gutterBottom>
          Blood Separator Centrifuge Dashboard
        </Typography>
        
        <Box display="flex" gap={2} alignItems="center">
          <Chip
            label={isConnected ? 'Connected' : isConnecting ? 'Connecting...' : 'Disconnected'}
            color={isConnected ? 'success' : isConnecting ? 'warning' : 'error'}
            variant="outlined"
          />
          
          {mqttConnectionStatus && (
            <Chip
              label={`MQTT: ${mqttConnectionStatus.isConnected ? 'Connected' : 'Disconnected'}`}
              color={mqttConnectionStatus.isConnected ? 'success' : 'error'}
              variant="outlined"
            />
          )}
        </Box>
      </Box>

      {/* Error alerts */}
      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}
      
      {signalRError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          SignalR: {signalRError}
        </Alert>
      )}

      <Grid container spacing={3}>
        {/* Device Cards */}
        <Grid item xs={12}>
          <Typography variant="h5" gutterBottom>
            Devices ({devices.length})
          </Typography>
          <Grid container spacing={2}>
            {devices.map((device) => (
              <Grid item xs={12} sm={6} md={4} key={device.deviceId}>
                <DeviceCard
                  device={device}
                  onClick={() => setSelectedDevice(device.deviceId)}
                />
              </Grid>
            ))}
          </Grid>
        </Grid>

        {/* Selected Device Details */}
        {selectedDeviceData && (
          <>
            <Grid item xs={12}>
              <Typography variant="h5" gutterBottom>
                Device Details: {selectedDevice}
              </Typography>
            </Grid>

            {/* Real-time Metrics */}
            {selectedDeviceData.latestTelemetry && (
              <Grid item xs={12}>
                <Paper sx={{ p: 2 }}>
                  <Typography variant="h6" gutterBottom>
                    Current Metrics
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={6} sm={3}>
                      <Card variant="outlined">
                        <CardContent>
                          <Typography color="text.secondary" gutterBottom>
                            RPM
                          </Typography>
                          <Typography variant="h4">
                            {selectedDeviceData.latestTelemetry.rpm}
                          </Typography>
                        </CardContent>
                      </Card>
                    </Grid>
                    <Grid item xs={6} sm={3}>
                      <Card variant="outlined">
                        <CardContent>
                          <Typography color="text.secondary" gutterBottom>
                            Temperature
                          </Typography>
                          <Typography variant="h4">
                            {selectedDeviceData.latestTelemetry.temperature.toFixed(1)}°C
                          </Typography>
                        </CardContent>
                      </Card>
                    </Grid>
                    <Grid item xs={6} sm={3}>
                      <Card variant="outlined">
                        <CardContent>
                          <Typography color="text.secondary" gutterBottom>
                            Pressure
                          </Typography>
                          <Typography variant="h4">
                            {selectedDeviceData.latestTelemetry.pressure} PSI
                          </Typography>
                        </CardContent>
                      </Card>
                    </Grid>
                    <Grid item xs={6} sm={3}>
                      <Card variant="outlined">
                        <CardContent>
                          <Typography color="text.secondary" gutterBottom>
                            Status
                          </Typography>
                          <Typography variant="h6">
                            {selectedDeviceData.latestTelemetry.status}
                          </Typography>
                        </CardContent>
                      </Card>
                    </Grid>
                  </Grid>
                </Paper>
              </Grid>
            )}

            {/* Charts */}
            {telemetryHistory.length > 0 && (
              <>
                <Grid item xs={12} md={6}>
                  <Paper sx={{ p: 2 }}>
                    <TelemetryChart
                      data={telemetryHistory}
                      metric="rpm"
                      title="RPM"
                      color="#1976d2"
                      unit="RPM"
                    />
                  </Paper>
                </Grid>
                <Grid item xs={12} md={6}>
                  <Paper sx={{ p: 2 }}>
                    <TelemetryChart
                      data={telemetryHistory}
                      metric="temperature"
                      title="Temperature"
                      color="#d32f2f"
                      unit="°C"
                    />
                  </Paper>
                </Grid>
                <Grid item xs={12} md={6}>
                  <Paper sx={{ p: 2 }}>
                    <TelemetryChart
                      data={telemetryHistory}
                      metric="pressure"
                      title="Pressure"
                      color="#388e3c"
                      unit="PSI"
                    />
                  </Paper>
                </Grid>
                <Grid item xs={12} md={6}>
                  <Paper sx={{ p: 2 }}>
                    <TelemetryChart
                      data={telemetryHistory}
                      metric="powerConsumption"
                      title="Power Consumption"
                      color="#f57c00"
                      unit="kW"
                    />
                  </Paper>
                </Grid>
              </>
            )}
          </>
        )}
      </Grid>
    </Container>
  );
};

export default Dashboard;