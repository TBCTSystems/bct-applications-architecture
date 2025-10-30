import React, { useState } from 'react';
import { Play, RotateCw, AlertCircle, CheckCircle } from 'lucide-react';
import axios from 'axios';

export default function AgentControls() {
  const [loading, setLoading] = useState({});
  const [notifications, setNotifications] = useState([]);

  const addNotification = (type, message) => {
    const id = Date.now();
    setNotifications(prev => [...prev, { id, type, message }]);
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, 5000);
  };

  const restartAgent = async (agentType) => {
    try {
      setLoading(prev => ({ ...prev, [agentType]: true }));
      const response = await axios.post(`/api/agent/${agentType}/restart`);
      addNotification('success', `${agentType.toUpperCase()} agent restarted successfully`);
    } catch (error) {
      addNotification('error', `Failed to restart ${agentType.toUpperCase()} agent: ${error.message}`);
    } finally {
      setLoading(prev => ({ ...prev, [agentType]: false }));
    }
  };

  return (
    <>
      {/* Toast Notifications */}
      <div className="fixed top-4 right-4 z-50 space-y-2">
        {notifications.map(notification => (
          <div
            key={notification.id}
            className={`flex items-center space-x-3 p-4 rounded-lg shadow-lg ${
              notification.type === 'success'
                ? 'bg-green-100 dark:bg-green-900 border border-green-200 dark:border-green-800'
                : 'bg-red-100 dark:bg-red-900 border border-red-200 dark:border-red-800'
            } animate-slide-in`}
          >
            {notification.type === 'success' ? (
              <CheckCircle className="w-5 h-5 text-green-600 dark:text-green-400" />
            ) : (
              <AlertCircle className="w-5 h-5 text-red-600 dark:text-red-400" />
            )}
            <p className={`text-sm font-medium ${
              notification.type === 'success'
                ? 'text-green-800 dark:text-green-200'
                : 'text-red-800 dark:text-red-200'
            }`}>
              {notification.message}
            </p>
          </div>
        ))}
      </div>

      {/* Control Panel */}
      <div className="card">
        <div className="flex items-center space-x-3 mb-6">
          <div className="p-2 rounded-lg bg-indigo-100 dark:bg-indigo-900/30">
            <Play className="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Agent Controls
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Manually trigger agent operations
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* ACME Agent Controls */}
          <div className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white">ACME Agent</h4>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Server certificate management
                </p>
              </div>
              <div className="p-2 rounded-lg bg-blue-100 dark:bg-blue-900/30">
                <RotateCw className="w-4 h-4 text-blue-600 dark:text-blue-400" />
              </div>
            </div>

            <div className="space-y-2">
              <button
                onClick={() => restartAgent('acme')}
                disabled={loading.acme}
                className="w-full btn-primary disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center space-x-2"
              >
                {loading.acme ? (
                  <>
                    <RotateCw className="w-4 h-4 animate-spin" />
                    <span>Restarting...</span>
                  </>
                ) : (
                  <>
                    <RotateCw className="w-4 h-4" />
                    <span>Force Renewal</span>
                  </>
                )}
              </button>

              <p className="text-xs text-gray-500 dark:text-gray-400 text-center">
                Restarts the ACME agent container to trigger immediate certificate check
              </p>
            </div>
          </div>

          {/* EST Agent Controls */}
          <div className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white">EST Agent</h4>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Client certificate management
                </p>
              </div>
              <div className="p-2 rounded-lg bg-green-100 dark:bg-green-900/30">
                <RotateCw className="w-4 h-4 text-green-600 dark:text-green-400" />
              </div>
            </div>

            <div className="space-y-2">
              <button
                onClick={() => restartAgent('est')}
                disabled={loading.est}
                className="w-full btn-primary disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center space-x-2"
              >
                {loading.est ? (
                  <>
                    <RotateCw className="w-4 h-4 animate-spin" />
                    <span>Restarting...</span>
                  </>
                ) : (
                  <>
                    <RotateCw className="w-4 h-4" />
                    <span>Force Enrollment</span>
                  </>
                )}
              </button>

              <p className="text-xs text-gray-500 dark:text-gray-400 text-center">
                Restarts the EST agent container to trigger immediate certificate check
              </p>
            </div>
          </div>
        </div>

        {/* Warning Note */}
        <div className="mt-6 p-4 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg">
          <div className="flex items-start space-x-3">
            <AlertCircle className="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm font-medium text-yellow-800 dark:text-yellow-200">
                Important Notes
              </p>
              <ul className="mt-2 text-xs text-yellow-700 dark:text-yellow-300 space-y-1 list-disc list-inside">
                <li>Restarting an agent will interrupt its current operation</li>
                <li>The agent will resume normal operation after restart</li>
                <li>Use this feature for testing or to force immediate certificate checks</li>
                <li>Requires Docker socket access in the web-ui container</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
