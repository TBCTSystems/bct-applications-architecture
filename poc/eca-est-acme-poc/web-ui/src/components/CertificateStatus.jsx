import React, { useState, useEffect } from 'react';
import { Shield, CheckCircle, AlertTriangle, XCircle, Clock } from 'lucide-react';
import axios from 'axios';
import { formatDistanceToNow } from 'date-fns';

export default function CertificateStatus({ refreshTrigger }) {
  const [certificates, setCertificates] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchCertificates();
  }, [refreshTrigger]);

  const fetchCertificates = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await axios.get('/api/certificates');
      setCertificates(response.data.certificates);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="w-5 h-5 text-green-600 dark:text-green-400" />;
      case 'warning':
        return <AlertTriangle className="w-5 h-5 text-yellow-600 dark:text-yellow-400" />;
      case 'error':
        return <XCircle className="w-5 h-5 text-red-600 dark:text-red-400" />;
      default:
        return <Shield className="w-5 h-5 text-gray-600 dark:text-gray-400" />;
    }
  };

  const getStatusBadge = (status) => {
    switch (status) {
      case 'healthy':
        return <span className="badge-success">Healthy</span>;
      case 'warning':
        return <span className="badge-warning">Warning</span>;
      case 'error':
        return <span className="badge-error">Error</span>;
      case 'no-data':
        return <span className="badge-info">No Data</span>;
      default:
        return <span className="badge">Unknown</span>;
    }
  };

  return (
    <div className="card">
      <div className="flex items-center space-x-3 mb-6">
        <div className="p-2 rounded-lg bg-purple-100 dark:bg-purple-900/30">
          <Shield className="w-5 h-5 text-purple-600 dark:text-purple-400" />
        </div>
        <div>
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Certificate Status
          </h3>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Recent certificate lifecycle events
          </p>
        </div>
      </div>

      {loading && (
        <div className="space-y-4">
          {[1, 2].map((i) => (
            <div key={i} className="loading-shimmer h-24 rounded-lg" />
          ))}
        </div>
      )}

      {error && (
        <div className="text-red-600 dark:text-red-400">
          Failed to load certificate status: {error}
        </div>
      )}

      {!loading && !error && certificates && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {Object.entries(certificates).map(([type, cert]) => (
            <div
              key={type}
              className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg hover:shadow-md transition-shadow"
            >
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center space-x-2">
                  {getStatusIcon(cert.status)}
                  <span className="font-semibold text-gray-900 dark:text-white">
                    {type.toUpperCase()}
                  </span>
                </div>
                {getStatusBadge(cert.status)}
              </div>

              {cert.lastSeen && (
                <div className="flex items-center space-x-2 text-sm text-gray-600 dark:text-gray-400 mb-2">
                  <Clock className="w-4 h-4" />
                  <span>
                    Last seen {formatDistanceToNow(new Date(cert.lastSeen), { addSuffix: true })}
                  </span>
                </div>
              )}

              {cert.events && cert.events.length > 0 && (
                <div className="mt-3 space-y-2">
                  <p className="text-xs font-semibold text-gray-700 dark:text-gray-300 uppercase">
                    Recent Events
                  </p>
                  <div className="space-y-1 max-h-32 overflow-y-auto">
                    {cert.events.slice(0, 5).map((event, idx) => (
                      <div
                        key={idx}
                        className="text-xs p-2 bg-gray-50 dark:bg-gray-700/50 rounded"
                      >
                        <div className="flex items-center justify-between">
                          <span className={`font-medium ${
                            event.severity === 'ERROR' ? 'text-red-600 dark:text-red-400' :
                            event.severity === 'WARN' ? 'text-yellow-600 dark:text-yellow-400' :
                            'text-gray-900 dark:text-white'
                          }`}>
                            {event.severity}
                          </span>
                          <span className="text-gray-500 dark:text-gray-400">
                            {formatDistanceToNow(new Date(event.timestamp), { addSuffix: true })}
                          </span>
                        </div>
                        <p className="text-gray-700 dark:text-gray-300 mt-1">
                          {event.message}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {cert.error && (
                <div className="mt-3 p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded text-xs text-red-800 dark:text-red-200">
                  {cert.error}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
