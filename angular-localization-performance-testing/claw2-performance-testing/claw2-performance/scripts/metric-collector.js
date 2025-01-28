// In your Angular service (for clarity):
/*
private logMetric(metricName: string, metric: Metric) {
  console.log(`METRIC ${metricName}: ${JSON.stringify(metric)}`);
}
*/

// Now the Puppeteer script:

// File: capture-metrics.js

const puppeteer = require('puppeteer');
const fs = require('fs');

// CONFIGURATIONS:
const RUNS = 100;             // number of times to measure
const URL = 'http://localhost:4200';
const CSV_PATH = 'metrics.csv';

/** Simple "sleep" function to pause execution for `ms` milliseconds. */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Appends a row to our CSV file.
 * If it's the first row, write the header.
 */
function appendCsvRow({ runIndex, fcp, lcp, ttfb }) {
  // If file doesn't exist, write a header line
  if (!fs.existsSync(CSV_PATH)) {
    fs.writeFileSync(CSV_PATH, 'Run,FCP,LCP,TTFB\n');
  }

  const row = `${runIndex},${fcp},${lcp},${ttfb}\n`;
  fs.appendFileSync(CSV_PATH, row);
}

(async () => {
  let browser = null;
  try {
    // 1. Launch Puppeteer
    browser = await puppeteer.launch({ headless: true });
    const page = await browser.newPage();

    // 2. Listen for console messages
    page.on('console', async (msg) => {
      const text = msg.text();

      // Debug info (optional)
      // console.log('DEBUG PUPPETEER saw text:', text);

      // If the console log has: "METRIC FCP: {...}"
      if (text.startsWith('METRIC FCP:')) {
        global.metricsForCurrentRun.fcp = text;
      } else if (text.startsWith('METRIC LCP:')) {
        global.metricsForCurrentRun.lcp = text;
      } else if (text.startsWith('METRIC TTFB:')) {
        global.metricsForCurrentRun.ttfb = text;
      }
    });

    // 3. Run multiple times
    for (let i = 1; i <= RUNS; i++) {
      console.log(`\n===== Run #${i} =====`);

      // Create fresh placeholders for each run
      global.metricsForCurrentRun = {
        fcp: 'NA',
        lcp: 'NA',
        ttfb: 'NA'
      };

      // 4. Navigate to the page (fresh each time)
      await page.goto(URL, { waitUntil: 'networkidle2' });

      // 5. Wait a bit for the metrics to be logged
      await sleep(2000);  // using sleep function above

      // 6. Extract numeric values from the logs we captured
      const { fcp, lcp, ttfb } = global.metricsForCurrentRun;

      /**
       * Example log string:
       * METRIC FCP: {"name":"FCP","value":304.9,"rating":"good",...}
       * We'll parse out the JSON part using substring + JSON.parse.
       */
      function extractValue(metricString) {
        if (metricString === 'NA') return 'NA';
        const jsonPart = metricString.substring(metricString.indexOf('{'));
        try {
          const obj = JSON.parse(jsonPart);
          return obj.value != null ? obj.value : 'NA';
        } catch (err) {
          return 'NA';
        }
      }

      const fcpValue = extractValue(fcp);
      const lcpValue = extractValue(lcp);
      const ttfbValue = extractValue(ttfb);

      console.log(`FCP: ${fcpValue}, LCP: ${lcpValue}, TTFB: ${ttfbValue}`);

      // 7. Write a row to CSV
      appendCsvRow({
        runIndex: i,
        fcp: fcpValue,
        lcp: lcpValue,
        ttfb: ttfbValue
      });
    }

    // 8. Cleanup
    await browser.close();
    console.log(`\nDone! Metrics saved to "${CSV_PATH}"`);

  } catch (error) {
    console.error('Error occurred:', error);
    if (browser) {
      await browser.close();
    }
    process.exit(1);
  }
})();
