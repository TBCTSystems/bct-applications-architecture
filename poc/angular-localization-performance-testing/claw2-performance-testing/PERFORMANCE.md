# Performance Metrics Documentation

This document describes the performance metrics collected for the Angular localization testing application.

## Core Web Vitals Metrics

### Time to First Byte (TTFB)
- **What it measures**: The time between the request for a page and when the first byte of the response arrives
- **Why it matters**: Indicates server response time and network conditions
- **Sample measurement**: 24ms (rating: good)


### First Contentful Paint (FCP)
- **What it measures**: The time from when the page starts loading to when any part of the page's content is rendered on the screen
- **Why it matters**: Indicates when users first see any content render, crucial for perceived performance
- **Sample measurement**: 205ms (rating: good)

### Largest Contentful Paint (LCP)
- **What it measures**: The time when the largest content element in the viewport becomes visible
- **Why it matters**: Indicates when the main content of the page has likely loaded
- **Sample measurement**: 211ms (rating: good)
- **Interpretation**:
  * < 2500ms: good
  * 2500-4000ms: needs improvement
  * > 4000ms: poor

## Understanding the Metrics Output

Each metric provides the following information:
```javascript
{
  name: "METRIC_NAME",    // The type of metric (FCP, TTFB, or LCP)
  value: number,         // The time in milliseconds
  rating: string,        // Performance rating: "good", "needs-improvement", or "poor"
  delta: number,         // The difference from the previous measurement
  id: string,           // Unique identifier for the measurement
  navigationType: string // How the page was accessed (e.g., "reload", "back_forward", "navigate")
}
Sample Measurements
// Time to First Byte
TTFB: {
  name: "TTFB",
  value: 24,
  rating: "good",
  delta: 24,
  id: "v4-1737557124619-3174477340979",
  navigationType: "reload"
}

// First Contentful Paint
FCP: {
  name: "FCP",
  value: 205,
  rating: "good",
  delta: 205,
  id: "v4-1737557124619-7542573545292",
  navigationType: "reload"
}

// Largest Contentful Paint
LCP: {
  name: "LCP",
  value: 211,
  rating: "good",
  delta: 211,
  id: "v4-1737557124619-5535939328916",
  navigationType: "reload"
}
