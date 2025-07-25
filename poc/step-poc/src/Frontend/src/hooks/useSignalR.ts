import { useState, useEffect, useCallback, useRef } from 'react';
import { HubConnection, HubConnectionBuilder, LogLevel } from '@microsoft/signalr';
import { CentrifugeTelemetryData, DeviceStatusData, DeviceAlertData, ConnectionStatus } from '../types/telemetry';

interface SignalRState {
  connection: HubConnection | null;
  isConnected: boolean;
  isConnecting: boolean;
  error: string | null;
  connectionId: string | null;
}

interface SignalRData {
  latestTelemetry: CentrifugeTelemetryData | null;
  latestStatus: DeviceStatusData | null;
  latestAlert: DeviceAlertData | null;
  mqttConnectionStatus: ConnectionStatus | null;
}

interface UseSignalRReturn extends SignalRState, SignalRData {
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  joinDeviceGroup: (deviceId: string) => Promise<void>;
  leaveDeviceGroup: (deviceId: string) => Promise<void>;
  joinAllDevicesGroup: () => Promise<void>;
  leaveAllDevicesGroup: () => Promise<void>;
}

const SIGNALR_URL = process.env.REACT_APP_SIGNALR_URL || 'http://localhost:5000/telemetryHub';

export const useSignalR = (): UseSignalRReturn => {
  const [state, setState] = useState<SignalRState>({
    connection: null,
    isConnected: false,
    isConnecting: false,
    error: null,
    connectionId: null,
  });

  const [data, setData] = useState<SignalRData>({
    latestTelemetry: null,
    latestStatus: null,
    latestAlert: null,
    mqttConnectionStatus: null,
  });

  const connectionRef = useRef<HubConnection | null>(null);

  const connect = useCallback(async () => {
    if (state.isConnected || state.isConnecting) {
      return;
    }

    setState(prev => ({ ...prev, isConnecting: true, error: null }));

    try {
      const connection = new HubConnectionBuilder()
        .withUrl(SIGNALR_URL)
        .withAutomaticReconnect({
          nextRetryDelayInMilliseconds: (retryContext) => {
            // Exponential backoff: 2s, 4s, 8s, 16s, then 30s
            if (retryContext.previousRetryCount < 4) {
              return Math.pow(2, retryContext.previousRetryCount + 1) * 1000;
            }
            return 30000;
          }
        })
        .configureLogging(LogLevel.Information)
        .build();

      // Connection event handlers
      connection.onclose((error) => {
        console.log('SignalR connection closed:', error);
        setState(prev => ({ 
          ...prev, 
          isConnected: false, 
          isConnecting: false,
          error: error?.message || 'Connection closed'
        }));
      });

      connection.onreconnecting((error) => {
        console.log('SignalR reconnecting:', error);
        setState(prev => ({ 
          ...prev, 
          isConnected: false, 
          isConnecting: true,
          error: 'Reconnecting...'
        }));
      });

      connection.onreconnected((connectionId) => {
        console.log('SignalR reconnected:', connectionId);
        setState(prev => ({ 
          ...prev, 
          isConnected: true, 
          isConnecting: false,
          error: null,
          connectionId: connectionId || null
        }));
      });

      // Message handlers
      connection.on('ConnectionEstablished', (data) => {
        console.log('SignalR connection established:', data);
        setState(prev => ({ 
          ...prev, 
          connectionId: data.connectionId,
          error: null
        }));
      });

      connection.on('TelemetryUpdate', (telemetry: CentrifugeTelemetryData) => {
        console.log('Received telemetry update:', telemetry);
        setData(prev => ({ ...prev, latestTelemetry: telemetry }));
      });

      connection.on('StatusUpdate', (status: DeviceStatusData) => {
        console.log('Received status update:', status);
        setData(prev => ({ ...prev, latestStatus: status }));
      });

      connection.on('AlertUpdate', (alert: DeviceAlertData) => {
        console.log('Received alert update:', alert);
        setData(prev => ({ ...prev, latestAlert: alert }));
      });

      connection.on('MqttConnectionStatusChanged', (status: ConnectionStatus) => {
        console.log('MQTT connection status changed:', status);
        setData(prev => ({ ...prev, mqttConnectionStatus: status }));
      });

      connection.on('JoinedDeviceGroup', (data) => {
        console.log('Joined device group:', data);
      });

      connection.on('JoinedAllDevicesGroup', (data) => {
        console.log('Joined all devices group:', data);
      });

      connection.on('Pong', (timestamp) => {
        console.log('Received pong:', timestamp);
      });

      // Start the connection
      await connection.start();
      
      connectionRef.current = connection;
      setState(prev => ({ 
        ...prev, 
        connection, 
        isConnected: true, 
        isConnecting: false,
        error: null
      }));

      console.log('SignalR connected successfully');

    } catch (error) {
      console.error('SignalR connection failed:', error);
      setState(prev => ({ 
        ...prev, 
        isConnecting: false,
        error: error instanceof Error ? error.message : 'Connection failed'
      }));
    }
  }, [state.isConnected, state.isConnecting]);

  const disconnect = useCallback(async () => {
    if (connectionRef.current) {
      try {
        await connectionRef.current.stop();
        connectionRef.current = null;
        setState(prev => ({ 
          ...prev, 
          connection: null, 
          isConnected: false, 
          isConnecting: false,
          connectionId: null,
          error: null
        }));
        console.log('SignalR disconnected');
      } catch (error) {
        console.error('Error disconnecting SignalR:', error);
      }
    }
  }, []);

  const joinDeviceGroup = useCallback(async (deviceId: string) => {
    if (connectionRef.current && state.isConnected) {
      try {
        await connectionRef.current.invoke('JoinDeviceGroup', deviceId);
      } catch (error) {
        console.error('Error joining device group:', error);
      }
    }
  }, [state.isConnected]);

  const leaveDeviceGroup = useCallback(async (deviceId: string) => {
    if (connectionRef.current && state.isConnected) {
      try {
        await connectionRef.current.invoke('LeaveDeviceGroup', deviceId);
      } catch (error) {
        console.error('Error leaving device group:', error);
      }
    }
  }, [state.isConnected]);

  const joinAllDevicesGroup = useCallback(async () => {
    if (connectionRef.current && state.isConnected) {
      try {
        await connectionRef.current.invoke('JoinAllDevicesGroup');
      } catch (error) {
        console.error('Error joining all devices group:', error);
      }
    }
  }, [state.isConnected]);

  const leaveAllDevicesGroup = useCallback(async () => {
    if (connectionRef.current && state.isConnected) {
      try {
        await connectionRef.current.invoke('LeaveAllDevicesGroup');
      } catch (error) {
        console.error('Error leaving all devices group:', error);
      }
    }
  }, [state.isConnected]);

  // Auto-connect on mount
  useEffect(() => {
    connect();

    // Cleanup on unmount
    return () => {
      disconnect();
    };
  }, []);

  return {
    ...state,
    ...data,
    connect,
    disconnect,
    joinDeviceGroup,
    leaveDeviceGroup,
    joinAllDevicesGroup,
    leaveAllDevicesGroup,
  };
};