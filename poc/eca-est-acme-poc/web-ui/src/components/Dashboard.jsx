import React, { useState, useEffect } from 'react';
import { RefreshCw } from 'lucide-react';
import StatsCards from './StatsCards';
import AgentStatus from './AgentStatus';
import CertificateStatus from './CertificateStatus';
import LogStream from './LogStream';
import AgentControls from './AgentControls';

export default function Dashboard() {
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [refreshInterval, setRefreshInterval] = useState(5000); // 5 seconds
  const [lastRefresh, setLastRefresh] = useState(new Date());

  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      setLastRefresh(new Date());
    }, refreshInterval);

    return () => clearInterval(interval);
  }, [autoRefresh, refreshInterval]);

  const handleManualRefresh = () => {
    setLastRefresh(new Date());
  };

  return (
    <div className="space-y-6">
      {/* Dashboard Controls */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center space-y-4 sm:space-y-0">
        <div>
          <h2 className="text-3xl font-bold text-gray-900 dark:text-white">
            Certificate Management Dashboard
          </h2>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Real-time monitoring of ACME and EST certificate agents
          </p>
        </div>

        <div className="flex items-center space-x-3">
          {/* Auto-refresh toggle */}
          <label className="flex items-center space-x-2 cursor-pointer">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
              className="w-4 h-4 text-primary-600 border-gray-300 rounded focus:ring-primary-500"
            />
            <span className="text-sm text-gray-700 dark:text-gray-300">
              Auto-refresh
            </span>
          </label>

          {/* Refresh interval selector */}
          {autoRefresh && (
            <select
              value={refreshInterval}
              onChange={(e) => setRefreshInterval(Number(e.target.value))}
              className="text-sm border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:border-primary-500 focus:ring-primary-500 dark:bg-gray-700 dark:text-gray-300"
            >
              <option value={5000}>5s</option>
              <option value={10000}>10s</option>
              <option value={30000}>30s</option>
              <option value={60000}>60s</option>
            </select>
          )}

          {/* Manual refresh button */}
          <button
            onClick={handleManualRefresh}
            className="btn-secondary flex items-center space-x-2"
          >
            <RefreshCw className="w-4 h-4" />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Stats Overview */}
      <StatsCards refreshTrigger={lastRefresh} />

      {/* Agent Status Cards */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <AgentStatus agentType="acme" refreshTrigger={lastRefresh} />
        <AgentStatus agentType="est" refreshTrigger={lastRefresh} />
      </div>

      {/* Certificate Status */}
      <CertificateStatus refreshTrigger={lastRefresh} />

      {/* Agent Controls */}
      <AgentControls />

      {/* Log Stream */}
      <LogStream refreshTrigger={lastRefresh} />
    </div>
  );
}
