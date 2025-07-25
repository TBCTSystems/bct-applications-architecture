import React from 'react';
import { Card, CardContent, Typography, Chip, Box, Grid } from '@mui/material';
import { DeviceSummary } from '../types/telemetry';
import { formatDistanceToNow } from 'date-fns';

interface DeviceCardProps {
  device: DeviceSummary;
  onClick?: () => void;
}

const DeviceCard: React.FC<DeviceCardProps> = ({ device, onClick }) => {
  const getStatusColor = (status: string, isConnected: boolean) => {
    if (!isConnected) return 'error';
    switch (status.toLowerCase()) {
      case 'running': return 'success';
      case 'warning': return 'warning';
      case 'stopped': return 'error';
      default: return 'default';
    }
  };

  const formatValue = (value: number, unit: string, decimals: number = 1) => {
    return `${value.toFixed(decimals)} ${unit}`;
  };

  return (
    <Card 
      sx={{ 
        cursor: onClick ? 'pointer' : 'default',
        '&:hover': onClick ? { boxShadow: 3 } : {},
        height: '100%'
      }}
      onClick={onClick}
    >
      <CardContent>
        <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
          <Typography variant="h6" component="h2">
            {device.deviceId}
          </Typography>
          <Chip
            label={device.isConnected ? device.status : 'Offline'}
            color={getStatusColor(device.status, device.isConnected)}
            size="small"
          />
        </Box>

        <Typography variant="body2" color="text.secondary" gutterBottom>
          Last seen: {formatDistanceToNow(new Date(device.lastSeen), { addSuffix: true })}
        </Typography>

        {device.latestTelemetry && (
          <Grid container spacing={1} mt={1}>
            <Grid item xs={6}>
              <Typography variant="body2">
                <strong>RPM:</strong> {device.latestTelemetry.rpm}
              </Typography>
            </Grid>
            <Grid item xs={6}>
              <Typography variant="body2">
                <strong>Temp:</strong> {formatValue(device.latestTelemetry.temperature, '°C')}
              </Typography>
            </Grid>
            <Grid item xs={6}>
              <Typography variant="body2">
                <strong>Pressure:</strong> {device.latestTelemetry.pressure} PSI
              </Typography>
            </Grid>
            <Grid item xs={6}>
              <Typography variant="body2">
                <strong>Power:</strong> {formatValue(device.latestTelemetry.powerConsumption, 'kW')}
              </Typography>
            </Grid>
          </Grid>
        )}

        {device.latestStatus && (
          <Box mt={2}>
            <Typography variant="body2">
              <strong>Uptime:</strong> {formatValue(device.latestStatus.uptimeHours, 'h')}
            </Typography>
            <Typography variant="body2">
              <strong>Cycles:</strong> {device.latestStatus.totalCycles.toLocaleString()}
            </Typography>
          </Box>
        )}

        {device.recentAlerts.length > 0 && (
          <Box mt={2}>
            <Typography variant="body2" color="warning.main">
              <strong>Recent Alerts:</strong> {device.recentAlerts.length}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Latest: {device.recentAlerts[device.recentAlerts.length - 1].alertType}
            </Typography>
          </Box>
        )}
      </CardContent>
    </Card>
  );
};

export default DeviceCard;