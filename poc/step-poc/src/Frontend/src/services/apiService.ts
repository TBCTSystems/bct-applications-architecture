import axios from 'axios';
import { DeviceSummary, CentrifugeTelemetryData, DeviceStatusData, DeviceAlertData, TelemetryHistoryRequest } from '../types/telemetry';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:5000';

const apiClient = axios.create({
  baseURL: `${API_BASE_URL}/api`,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor for logging
apiClient.interceptors.request.use(
  (config) => {
    console.log(`API Request: ${config.method?.toUpperCase()} ${config.url}`);
    return config;
  },
  (error) => {
    console.error('API Request Error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => {
    console.log(`API Response: ${response.status} ${response.config.url}`);
    return response;
  },
  (error) => {
    console.error('API Response Error:', error.response?.status, error.response?.data);
    return Promise.reject(error);
  }
);

export class ApiService {
  // Device management
  static async getDevices(): Promise<DeviceSummary[]> {
    const response = await apiClient.get<DeviceSummary[]>('/telemetry/devices');
    return response.data;
  }

  static async getDevice(deviceId: string): Promise<DeviceSummary> {
    const response = await apiClient.get<DeviceSummary>(`/telemetry/devices/${deviceId}`);
    return response.data;
  }

  // Telemetry data
  static async getLatestTelemetry(deviceId: string): Promise<CentrifugeTelemetryData> {
    const response = await apiClient.get<CentrifugeTelemetryData>(`/telemetry/devices/${deviceId}/latest`);
    return response.data;
  }

  static async getTelemetryHistory(
    deviceId: string, 
    request: TelemetryHistoryRequest = {}
  ): Promise<CentrifugeTelemetryData[]> {
    const params = new URLSearchParams();
    
    if (request.startTime) params.append('startTime', request.startTime);
    if (request.endTime) params.append('endTime', request.endTime);
    if (request.limit) params.append('limit', request.limit.toString());
    
    const response = await apiClient.get<CentrifugeTelemetryData[]>(
      `/telemetry/devices/${deviceId}/history?${params.toString()}`
    );
    return response.data;
  }

  // Status data
  static async getStatusHistory(
    deviceId: string, 
    request: TelemetryHistoryRequest = {}
  ): Promise<DeviceStatusData[]> {
    const params = new URLSearchParams();
    
    if (request.startTime) params.append('startTime', request.startTime);
    if (request.endTime) params.append('endTime', request.endTime);
    if (request.limit) params.append('limit', request.limit.toString());
    
    const response = await apiClient.get<DeviceStatusData[]>(
      `/telemetry/devices/${deviceId}/status-history?${params.toString()}`
    );
    return response.data;
  }

  // Alert data
  static async getRecentAlerts(deviceId: string, count: number = 10): Promise<DeviceAlertData[]> {
    const response = await apiClient.get<DeviceAlertData[]>(
      `/telemetry/devices/${deviceId}/alerts?count=${count}`
    );
    return response.data;
  }

  // Health check
  static async getHealth(): Promise<any> {
    const response = await apiClient.get('/health');
    return response.data;
  }
}

export default ApiService;