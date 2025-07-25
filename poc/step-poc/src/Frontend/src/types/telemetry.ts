export interface CentrifugeTelemetryData {
  deviceId: string;
  timestamp: string;
  rpm: number;
  temperature: number;
  vibration: number;
  pressure: number;
  plasmaYield: number;
  plateletYield: number;
  redBloodCellYield: number;
  status: string;
  powerConsumption: number;
  cycleCount: number;
}

export interface DeviceStatusData {
  deviceId: string;
  timestamp: string;
  status: string;
  uptimeHours: number;
  softwareVersion: string;
  memoryUsagePercent: number;
  cpuUsagePercent: number;
  lastMaintenanceDate: string;
  totalCycles: number;
}

export interface DeviceAlertData {
  deviceId: string;
  timestamp: string;
  alertType: string;
  severity: string;
  message: string;
  parameters: Record<string, any>;
}

export interface DeviceSummary {
  deviceId: string;
  status: string;
  lastSeen: string;
  latestTelemetry?: CentrifugeTelemetryData;
  latestStatus?: DeviceStatusData;
  recentAlerts: DeviceAlertData[];
  isConnected: boolean;
  uptime: string;
}

export interface ConnectionStatus {
  status: string;
  isConnected: boolean;
  timestamp: string;
}

export interface TelemetryHistoryRequest {
  startTime?: string;
  endTime?: string;
  limit?: number;
  metricType?: string;
}