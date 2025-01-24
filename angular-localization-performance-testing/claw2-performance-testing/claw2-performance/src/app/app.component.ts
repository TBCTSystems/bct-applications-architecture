import { Component, OnInit } from '@angular/core';
import { TranslocoService } from '@jsverse/transloco';
import { WebVitalsService } from './performance/web-vitals.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit {
  constructor(
    private translationService: TranslocoService,
    private webVitalsService: WebVitalsService
  ) {}

  ngOnInit() {
    // Start measuring performance metrics
    this.webVitalsService.measureAll();
    
    // Initialize translations
    this.translationService.setActiveLang('en-US');
  }

  showMoreInfo = false;
  
  stats = [
    { label: 'stats.totalUsers', value: '1234' },
    { label: 'stats.activeSessions', value: '56' },
    { label: 'stats.responseTime', value: '120ms' },
    { label: 'stats.totalRevenue', value: '$1234.56' },
    { label: 'stats.date', value: '22/10/2021' }
  ];

  // Example user info (could be localized)
  user = {
    firstName: 'Alice',
    lastName: 'Smith',
    balance: 1530.75,        // currency field to localize
    joinedDate: new Date(2023, 5, 12), // date field
    email: 'jane.doe@example.com',
  };

  // Short paragraphs to demonstrate textual localization
  introText1 = `Welcome to our sample Angular page. We aim to provide a simple but 
                effective demonstration of text, dates, and currency formatting 
                that can be localized. Feel free to explore and test translations!`;

  introText2 = `Below, you will find some sample user data. We encourage you to 
                localize the text, currency values, and dates to see how different 
                locales handle these details.`;

  // Example transactions with date, item, price, quantity, etc.
  transactions = [
    {
      date: new Date(2024, 10, 5),
      item: 'Office Chair',
      price: 120.50,
      quantity: 2
    },
    {
      date: new Date(2025, 0, 17),
      item: 'Laptop Stand',
      price: 45.99,
      quantity: 1
    },
    {
      date: new Date(2025, 1, 3),
      item: 'Wireless Mouse',
      price: 25.0,
      quantity: 3
    }
  ];

  // Utility method to calculate total cost for a transaction
  getTotal(transaction: { price: number; quantity: number }) {
    return transaction.price * transaction.quantity;
  }

  toggleInfo() {
    this.showMoreInfo = !this.showMoreInfo;
  }
}
