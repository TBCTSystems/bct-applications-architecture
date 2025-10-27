import React, { useState, useEffect } from 'react';
import { Activity, Clock, AlertCircle } from 'lucide-react';
import axios from 'axios';
import { formatDistanceToNow } from 'date-fns';

export default function AgentStatus({ agentType, refreshTrigger }) {
  const [agent, setAgent] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchAgentStatus();
  }, [agentType, refreshTrigger]);

  const fetchAgentStatus = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await axios.get('/api/agents/status');
      setAgent(response.data.agents[agentType]);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'healthy':
        return 'bg-green-500';
      case 'warning':
        return 'bg-yellow-500';
      case 'stale':
      case 'error':
        return 'bg-red-500';
      default:
        return 'bg-gray-500';
    }
  };

  const getStatusText = (status) => {
    switch (status) {
      case 'healthy':
        return 'Healthy';
      case 'warning':
        return 'Warning';
      case 'stale':
        return 'Stale';
      case 'error':
        return 'Error';
      case 'no-data':
        return 'No Data';
      default:
        return 'Unknown';
    }
  };

  const agentName = agentType.toUpperCase();

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className={`p-2 rounded-lg ${agentType === 'acme' ? 'bg-blue-100 dark:bg-blue-900/30' : 'bg-green-100 dark:bg-green-900/30'}`}>
            <Activity className={`w-5 h-5 ${agentType === 'acme' ? 'text-blue-600 dark:text-blue-400' : 'text-green-600 dark:text-green-400'}`} />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              {agentName} Agent
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {agentType === 'acme' ? 'Server Certificate Management' : 'Client Certificate Management'}
            </p>
          </div>
        </div>

        {!loading && agent && (
          <div className="flex items-center space-x-2">
            <div className={`w-3 h-3 rounded-full ${getStatusColor(agent.status)} ${agent.status === 'healthy' ? 'animate-pulse' : ''}`} />
            <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
              {getStatusText(agent.status)}
            </span>
          </div>
        )}
      </div>

      {loading && (
        <div className="space-y-3">
          <div className="loading-shimmer h-4 w-3/4 rounded" />
          <div className="loading-shimmer h-4 w-1/2 rounded" />
        </div>
      )}

      {error && (
        <div className="flex items-center space-x-2 text-red-600 dark:text-red-400">
          <AlertCircle className="w-4 h-4" />
          <span className="text-sm">Failed to load agent status</span>
        </div>
      )}

      {!loading && !error && agent && (
        <div className="space-y-3">
          {agent.lastHeartbeat && (
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-2 text-gray-600 dark:text-gray-400">
                <Clock className="w-4 h-4" />
                <span className="text-sm">Last heartbeat</span>
              </div>
              <span className="text-sm font-medium text-gray-900 dark:text-white">
                {formatDistanceToNow(new Date(agent.lastHeartbeat), { addSuffix: true })}
              </span>
            </div>
          )}

          {agent.ageSeconds !== undefined && (
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Age</span>
              <span className="text-sm font-medium text-gray-900 dark:text-white">
                {agent.ageSeconds}s
              </span>
            </div>
          )}

          {agent.status === 'no-data' && (
            <div className="mt-4 p-3 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg">
              <p className="text-sm text-yellow-800 dark:text-yellow-200">
                No recent logs detected. Agent may not be running.
              </p>
            </div>
          )}

          {agent.error && (
            <div className="mt-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
              <p className="text-sm text-red-800 dark:text-red-200">
                {agent.error}
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
