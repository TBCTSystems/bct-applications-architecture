import React, { useState, useEffect } from 'react';
import { Activity, AlertTriangle, XCircle, FileText } from 'lucide-react';
import axios from 'axios';

export default function StatsCards({ refreshTrigger }) {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchStats();
  }, [refreshTrigger]);

  const fetchStats = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await axios.get('/api/stats');
      setStats(response.data.stats);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const statCards = [
    {
      title: 'ACME Logs',
      value: stats?.acme_total || 0,
      icon: Activity,
      color: 'text-blue-600 dark:text-blue-400',
      bgColor: 'bg-blue-100 dark:bg-blue-900/30'
    },
    {
      title: 'EST Logs',
      value: stats?.est_total || 0,
      icon: Activity,
      color: 'text-green-600 dark:text-green-400',
      bgColor: 'bg-green-100 dark:bg-green-900/30'
    },
    {
      title: 'Warnings',
      value: stats?.warnings || 0,
      icon: AlertTriangle,
      color: 'text-yellow-600 dark:text-yellow-400',
      bgColor: 'bg-yellow-100 dark:bg-yellow-900/30'
    },
    {
      title: 'Errors',
      value: stats?.errors || 0,
      icon: XCircle,
      color: 'text-red-600 dark:text-red-400',
      bgColor: 'bg-red-100 dark:bg-red-900/30'
    }
  ];

  if (error) {
    return (
      <div className="card bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800">
        <p className="text-red-800 dark:text-red-200">Failed to load stats: {error}</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      {statCards.map((stat, index) => (
        <div key={index} className="card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-600 dark:text-gray-400">
                {stat.title}
              </p>
              <p className={`text-3xl font-bold mt-2 ${loading ? 'loading-shimmer h-10 w-20 rounded' : ''}`}>
                {!loading && stat.value}
              </p>
            </div>
            <div className={`p-3 rounded-lg ${stat.bgColor}`}>
              <stat.icon className={`w-6 h-6 ${stat.color}`} />
            </div>
          </div>
          <div className="mt-4 flex items-center text-xs text-gray-500 dark:text-gray-400">
            <FileText className="w-3 h-3 mr-1" />
            Last hour
          </div>
        </div>
      ))}
    </div>
  );
}
