import React from 'react';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  ChartOptions,
} from 'chart.js';
import { CentrifugeTelemetryData } from '../types/telemetry';
import { format } from 'date-fns';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

interface TelemetryChartProps {
  data: CentrifugeTelemetryData[];
  metric: 'rpm' | 'temperature' | 'pressure' | 'powerConsumption' | 'vibration';
  title: string;
  color: string;
  unit: string;
  height?: number;
}

const TelemetryChart: React.FC<TelemetryChartProps> = ({
  data,
  metric,
  title,
  color,
  unit,
  height = 300
}) => {
  const chartData = {
    labels: data.map(item => format(new Date(item.timestamp), 'HH:mm:ss')),
    datasets: [
      {
        label: title,
        data: data.map(item => item[metric]),
        borderColor: color,
        backgroundColor: color + '20',
        borderWidth: 2,
        fill: true,
        tension: 0.4,
        pointRadius: 2,
        pointHoverRadius: 4,
      },
    ],
  };

  const options: ChartOptions<'line'> = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: true,
        text: title,
      },
      tooltip: {
        callbacks: {
          label: (context) => {
            return `${context.dataset.label}: ${context.parsed.y.toFixed(2)} ${unit}`;
          },
        },
      },
    },
    scales: {
      x: {
        display: true,
        title: {
          display: true,
          text: 'Time',
        },
        ticks: {
          maxTicksLimit: 10,
        },
      },
      y: {
        display: true,
        title: {
          display: true,
          text: unit,
        },
        beginAtZero: metric === 'rpm' || metric === 'pressure',
      },
    },
    animation: {
      duration: 750,
    },
  };

  return (
    <div style={{ height: `${height}px`, width: '100%' }}>
      <Line data={chartData} options={options} />
    </div>
  );
};

export default TelemetryChart;