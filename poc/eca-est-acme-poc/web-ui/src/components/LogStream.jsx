import React, { useState, useEffect } from 'react';
import { FileText, Filter, Download, Search } from 'lucide-react';
import axios from 'axios';
import { formatDistanceToNow } from 'date-fns';

export default function LogStream({ refreshTrigger }) {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState('all');
  const [searchTerm, setSearchTerm] = useState('');
  const [limit, setLimit] = useState(50);

  useEffect(() => {
    fetchLogs();
  }, [refreshTrigger, filter, limit]);

  const fetchLogs = async () => {
    try {
      setLoading(true);
      setError(null);

      let query = '{agent_type=~"acme|est"}';
      if (filter === 'acme') {
        query = '{agent_type="acme"}';
      } else if (filter === 'est') {
        query = '{agent_type="est"}';
      } else if (filter === 'errors') {
        query = '{severity="ERROR"}';
      } else if (filter === 'warnings') {
        query = '{severity="WARN"}';
      }

      const response = await axios.get('/api/logs', {
        params: { query, limit }
      });

      setLogs(response.data.logs || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const getSeverityColor = (severity) => {
    switch (severity) {
      case 'ERROR':
        return 'text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20';
      case 'WARN':
        return 'text-yellow-600 dark:text-yellow-400 bg-yellow-50 dark:bg-yellow-900/20';
      case 'INFO':
        return 'text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-900/20';
      case 'DEBUG':
        return 'text-gray-600 dark:text-gray-400 bg-gray-50 dark:bg-gray-700/50';
      default:
        return 'text-gray-600 dark:text-gray-400 bg-gray-50 dark:bg-gray-700/50';
    }
  };

  const filteredLogs = logs.filter(log => {
    if (!searchTerm) return true;
    const searchLower = searchTerm.toLowerCase();
    return (
      log.message?.toLowerCase().includes(searchLower) ||
      log.severity?.toLowerCase().includes(searchLower) ||
      JSON.stringify(log.context || {}).toLowerCase().includes(searchLower)
    );
  });

  const downloadLogs = () => {
    const dataStr = JSON.stringify(filteredLogs, null, 2);
    const dataUri = 'data:application/json;charset=utf-8,' + encodeURIComponent(dataStr);
    const exportFileDefaultName = `eca-logs-${new Date().toISOString()}.json`;

    const linkElement = document.createElement('a');
    linkElement.setAttribute('href', dataUri);
    linkElement.setAttribute('download', exportFileDefaultName);
    linkElement.click();
  };

  return (
    <div className="card">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center space-x-3">
          <div className="p-2 rounded-lg bg-emerald-100 dark:bg-emerald-900/30">
            <FileText className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Log Stream
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Real-time agent logs from Loki
            </p>
          </div>
        </div>

        <button
          onClick={downloadLogs}
          className="btn-secondary flex items-center space-x-2"
          disabled={filteredLogs.length === 0}
        >
          <Download className="w-4 h-4" />
          <span>Export</span>
        </button>
      </div>

      {/* Controls */}
      <div className="flex flex-col sm:flex-row gap-4 mb-4">
        {/* Filter buttons */}
        <div className="flex flex-wrap gap-2">
          {['all', 'acme', 'est', 'errors', 'warnings'].map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                filter === f
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-gray-600'
              }`}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search logs..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:ring-2 focus:ring-primary-500 focus:border-primary-500 bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
          />
        </div>

        {/* Limit selector */}
        <select
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
          className="border border-gray-300 dark:border-gray-600 rounded-md px-3 py-2 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary-500"
        >
          <option value={25}>25 logs</option>
          <option value={50}>50 logs</option>
          <option value={100}>100 logs</option>
          <option value={200}>200 logs</option>
        </select>
      </div>

      {/* Log count */}
      <div className="mb-4 text-sm text-gray-600 dark:text-gray-400">
        Showing {filteredLogs.length} of {logs.length} logs
      </div>

      {/* Logs */}
      {loading && (
        <div className="space-y-2">
          {[1, 2, 3, 4, 5].map(i => (
            <div key={i} className="loading-shimmer h-20 rounded-lg" />
          ))}
        </div>
      )}

      {error && (
        <div className="p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-red-800 dark:text-red-200">
          Failed to load logs: {error}
        </div>
      )}

      {!loading && !error && filteredLogs.length === 0 && (
        <div className="text-center py-12">
          <FileText className="w-12 h-12 text-gray-400 mx-auto mb-4" />
          <p className="text-gray-600 dark:text-gray-400">No logs found</p>
        </div>
      )}

      {!loading && !error && filteredLogs.length > 0 && (
        <div className="space-y-2 max-h-[600px] overflow-y-auto">
          {filteredLogs.map((log, idx) => (
            <div
              key={idx}
              className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg hover:shadow-md transition-shadow"
            >
              <div className="flex items-start justify-between mb-2">
                <div className="flex items-center space-x-3">
                  <span className={`px-2 py-1 text-xs font-semibold rounded ${getSeverityColor(log.severity)}`}>
                    {log.severity || 'INFO'}
                  </span>
                  {log.labels?.agent_type && (
                    <span className="text-xs px-2 py-1 bg-gray-100 dark:bg-gray-700 rounded">
                      {log.labels.agent_type}
                    </span>
                  )}
                </div>
                <span className="text-xs text-gray-500 dark:text-gray-400">
                  {formatDistanceToNow(new Date(log.timestamp), { addSuffix: true })}
                </span>
              </div>

              <p className="text-sm text-gray-900 dark:text-white mb-2">
                {log.message}
              </p>

              {log.context && Object.keys(log.context).length > 0 && (
                <details className="mt-2">
                  <summary className="text-xs text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-white">
                    View context
                  </summary>
                  <pre className="mt-2 p-2 bg-gray-50 dark:bg-gray-800 rounded text-xs overflow-x-auto">
                    {JSON.stringify(log.context, null, 2)}
                  </pre>
                </details>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
