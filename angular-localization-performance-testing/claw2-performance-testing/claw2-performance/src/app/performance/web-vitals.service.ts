import { Injectable } from '@angular/core';
import { onFCP, onLCP, onTTFB, Metric } from 'web-vitals';
import { BehaviorSubject } from 'rxjs';

export interface PerformanceMetric {
  name: string;
  value: number;
  rating: 'good' | 'needs-improvement' | 'poor';
  delta: number;
  id: string;
  navigationType: string;
}

@Injectable({
  providedIn: 'root'
})
export class WebVitalsService {
  private fcpMetric = new BehaviorSubject<PerformanceMetric | null>(null);
  private lcpMetric = new BehaviorSubject<PerformanceMetric | null>(null);
  private ttfbMetric = new BehaviorSubject<PerformanceMetric | null>(null);
  
  fcpMetric$ = this.fcpMetric.asObservable();
  lcpMetric$ = this.lcpMetric.asObservable();
  ttfbMetric$ = this.ttfbMetric.asObservable();

  private logMetric(metricName: string, metric: Metric) {
    // Instead of console.log('METRIC FCP:', metric),
    // build a single string with JSON.stringify():
    console.log(`METRIC ${metricName}: ${JSON.stringify(metric)}`);
  }

  private createMetricObject(metric: Metric): PerformanceMetric {
    return {
      name: metric.name,
      value: metric.value,
      rating: metric.rating,
      delta: metric.delta,
      id: metric.id,
      navigationType: metric.navigationType
    };
  }

  measureFCP() {
    onFCP(metric => {
      this.logMetric('FCP', metric);
      this.fcpMetric.next(this.createMetricObject(metric));
    });
  }

  measureLCP() {
    onLCP(metric => {
      this.logMetric('LCP', metric);
      this.lcpMetric.next(this.createMetricObject(metric));
    });
  }

  measureTTFB() {
    onTTFB(metric => {
      this.logMetric('TTFB', metric);
      this.ttfbMetric.next(this.createMetricObject(metric));
    });
  }

  measureAll() {
    this.measureFCP();
    this.measureLCP();
    this.measureTTFB();
  }
}
