import React, { useState, useEffect } from 'react';
import { Moon, Sun, Activity, AlertCircle, CheckCircle, XCircle, RefreshCw } from 'lucide-react';
import Dashboard from './components/Dashboard';
import Header from './components/Header';
import { ThemeProvider, useTheme } from './context/ThemeContext';

function AppContent() {
  const { theme, toggleTheme } = useTheme();
  const [isOnline, setIsOnline] = useState(true);

  useEffect(() => {
    // Check backend health
    const checkHealth = async () => {
      try {
        const response = await fetch('/api/health');
        setIsOnline(response.ok);
      } catch (error) {
        setIsOnline(false);
      }
    };

    checkHealth();
    const interval = setInterval(checkHealth, 30000); // Check every 30s

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      <Header theme={theme} toggleTheme={toggleTheme} isOnline={isOnline} />
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Dashboard />
      </main>
      <footer className="bg-white dark:bg-gray-800 border-t border-gray-200 dark:border-gray-700 mt-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex flex-col md:flex-row justify-between items-center space-y-4 md:space-y-0">
            <div className="text-sm text-gray-600 dark:text-gray-400">
              <p>Edge Certificate Agent (ECA) Proof of Concept</p>
              <p className="mt-1">Autonomous certificate lifecycle management</p>
            </div>
            <div className="flex items-center space-x-4">
              <a
                href="https://github.com/yourusername/eca-poc"
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-primary-600 dark:text-primary-400 hover:underline"
              >
                Documentation
              </a>
              <span className="text-gray-300 dark:text-gray-600">|</span>
              <a
                href="http://localhost:3000"
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-primary-600 dark:text-primary-400 hover:underline"
              >
                Grafana Dashboard
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}

function App() {
  return (
    <ThemeProvider>
      <AppContent />
    </ThemeProvider>
  );
}

export default App;
