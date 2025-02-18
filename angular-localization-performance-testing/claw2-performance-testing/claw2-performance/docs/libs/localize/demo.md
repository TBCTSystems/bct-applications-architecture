
# Localization Demo

This project demonstrates Angular's localization features, including:

- [Basics](#basics)
- [Date Localization](#date-localization)
- [Currency Localization](#currency-localization)
- [Number Formatting](#number-formatting)
- [Pluralization](#pluralization)
- [Gender-Based Variations](#gender-based-variations)
- [Dynamic List Localization](#dynamic-list-localization)
- [Programmatic Localization](#programmatic-localization)
- [Useful Links](#useful-links)

## Basics

Below is an explanation of key concepts:

### `i18n` Attribute and `@@` Syntax
The `i18n` attribute marks translatable content in your templates.

The `@@` syntax assigns a unique identifier to a translatable string. For example:

```html
<h1 i18n="@@main-title">Welcome to the Localization Demo</h1>
```

In the extracted translation files:

```json
{
  "locale": "fa",
  "translations": {
    "main-title": "به نسخه نمایشی بومی سازی خوش آمدید"
  }
}
```

```json
{
  "locale": "ja",
  "translations": {
    "main-title": "ローカリゼーションデモへようこそ"
  }
}
```


### Translating Attributes
To localize attributes (e.g., `alt` for images), use the `i18n-` prefix:

```html
<img src="logo.png" i18n-alt="@@logo-alt" alt="Company logo" />
```

## Why Inject `LOCALE_ID` and `DEFAULT_CURRENCY_CODE`?

### `LOCALE_ID`

The `LOCALE_ID` token provides the current locale of the application, which is critical for:
- Formatting dates, numbers, and currencies appropriately.
- Dynamically adjusting UI text and functionality based on the user's language and regional preferences.

### `DEFAULT_CURRENCY_CODE`

The `DEFAULT_CURRENCY_CODE` token defines the default currency code for your application. It ensures:
- The `currency` pipe automatically uses the appropriate currency symbol.
- You can programmatically determine the currency for display.

These tokens are injected into components when you need to programmatically adjust behavior or display content.

## Using `LOCALE_ID`

```HTML
<!-- Current Locale Section -->
<h2 i18n="@@section-locale-title">Current Locale</h2>
<p i18n="@@section-locale-description">The current locale is:</p>
<p>{{ locale }}</p>
```

```typescript
constructor(@Inject(LOCALE_ID) public locale: string) {}
```

## Date Localization

### Example Code

```html
<!-- Date Localization Section -->
<h2 i18n="@@section-date-title">Date Localization</h2>
<p i18n="@@section-date-today">Today's date:</p>
<p>{{ today | date: 'longDate' }}</p>
```

### Explanation
The `date` pipe formats the date based on the current locale.
In Farsi (`fa`), it uses Persian text and numbers while maintaining the Gregorian calendar:
Example: ۱۶ ژانویهٔ ۲۰۲۵ (January 16, 2025).
In Japanese (`ja`), it formats the date with Kanji using the Gregorian calendar:
Example: 2025年1月16日.

### Important Notes
> Does not convert calendars: The date pipe always uses the Gregorian calendar internally.
For locales with non-Gregorian calendar systems (e.g., Persian or Lunar calendars), only the text (month/day names) and numbers are localized.

> Localized Formatting: The pipe **respects regional conventions** for date ordering (e.g., "day/month/year" vs. "month/day/year") and uses appropriate symbols.

## Currency Localization

### Example Code

```html
<!-- Currency Localization Section -->
<h2 i18n="@@section-currency-title">Currency Localization</h2>
<p i18n="@@section-currency-amount">Amount:</p>
<p>{{ amount | currency }}</p> <!-- Automatically uses DEFAULT_CURRENCY_CODE -->
<p i18n="@@section-currency-code">Currency Code: {{ currentCurrency }}</p>
```

### Explanation

> The `currency` pipe formats amounts based on the current locale's `DEFAULT_CURRENCY_CODE`. By default, the currency code is set to `USD` (United States Dollar). If you want to dynamically adjust the currency based on the locale, you must explicitly set `DEFAULT_CURRENCY_CODE` in `main.ts` as shown below.

```typescript
import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app/app.component';
import { DEFAULT_CURRENCY_CODE, LOCALE_ID } from '@angular/core';

bootstrapApplication(AppComponent, {
  providers: [
    {
      provide: DEFAULT_CURRENCY_CODE,
      useFactory: (locale: string) => {
        switch (locale) {
          case 'fa-IR':
          case 'fa':
            return 'IRR'; // Iranian Rial
          case 'ja-JP':
          case 'ja':
            return 'JPY'; // Japanese Yen
          default:
            return 'USD'; // Default to US Dollar
        }
      },
      deps: [LOCALE_ID],
    },
  ],
}).catch((err) => console.error(err));

```

> Warning: The `currency` pipe only updates the **symbol**, not the value. Ensure amounts match the currency through backend or UI logic.

---

## Number Formatting

### Example Code

```html
<!-- Number Formatting Section -->
<h2 i18n="@@section-number-title">Number Formatting</h2>
<p i18n="@@section-large-number">Large Number:</p>
<p>{{ largeNumber | number }}</p>
```

### Explanation

- The `number` pipe formats large numbers with locale-specific separators (e.g., commas or spaces).

---

## Pluralization

### Example Code

```html
<!-- Pluralization Section -->
<h2 i18n="@@section-plural-title">Pluralization</h2>
<label i18n="@@section-cart-label">Enter number of items in cart:</label>
<input type="number" [(ngModel)]="itemCount" />
<p>
  <ng-container i18n="@@section-cart-message">
    { itemCount, plural,
      =0 {Your cart is empty.}
      =1 {You have 1 item in your cart.}
      other {You have {{itemCount}} items in your cart.}
    }
  </ng-container>
</p>
```

Translation files:
```json
"section-cart-message": " {$ICU} ",
"5626341735168627022": "{VAR_PLURAL, plural, =0 {カートは空です。} =1 {カートに1つのアイテムがあります。} other {カートに{INTERPOLATION}個のアイテムがあります。}}",
```


> In cases that the value is calculated dynamically, it is easier to use a custom function with `$localize`. For example, assume you need to display a message like `You have X items in your cart` but the item count is calculated dynamically (e.g., products.length * factor) rather than being a simple bound variable.

- Use custom logic when pluralization logic requires complex calculations or procedural logic, the variable for pluralization is computed dynamically or not directly available in the template.
- Use `ICU` in templates when the value to pluralize is simple and directly available in the template and no advanced logic or external dependency is required.

## Gender-Based Variations

### Example Code

```html
<!-- Gender-Based Variations Section -->
<h2 i18n="@@section-gender-title">Gender-Based Text Variations</h2>
<label i18n="@@section-gender-label">Select Gender:</label>
<select [(ngModel)]="userGender">
  <option value="male" i18n="@@section-gender-male">Male</option>
  <option value="female" i18n="@@section-gender-female">Female</option>
  <option value="other" i18n="@@section-gender-other">Other</option>
</select>
<p>
  <ng-container i18n="@@section-gender-message">
    { userGender, select,
      male {Hello, Mr. {{ userName }}!}
      female {Hello, Ms. {{ userName }}!}
      other {Hello, {{ userName }}!}
    }
  </ng-container>
</p>
```

Translation file:
```json
"section-gender-message": " {$ICU} ",
"4606383290184133341": "{VAR_SELECT, select, male {こんにちは、{INTERPOLATION}さん！} female {こんにちは、{INTERPOLATION}さん！} other {こんにちは、{INTERPOLATION}さん！}}",
  ```

### Explanation

- Uses ICU expressions for `select` to handle gender-based variations.
- Translations must include ICU entries for gender-specific text.

---

## Dynamic List Localization

### Example Code

```html
<!-- Dynamic List Section -->
<h2 i18n="@@section-list-title">Product List</h2>
<p i18n="@@section-list-description">Here are some products available:</p>
<ul>
  <li *ngFor="let product of products">
    <span>{{ product.name }}</span> -
    <span i18n="@@section-list-price">Price:</span> {{ product.price | currency }}
  </li>
</ul>
```

---

## Programmatic Localization

### Example Code

```typescript
  constructor() {
    this.greeting = this.getLocalizedGreeting();
  }

  getLocalizedGreeting(): string {
    const hour = new Date().getHours();

    if (hour < 12) {
      return $localize`:@@morning-greeting:Good morning!`;
    } else if (hour < 18) {
      return $localize`:@@afternoon-greeting:Good afternoon!`;
    } else {
      return $localize`:@@evening-greeting:Good evening!`;
    }
  }
```

```HTML
<p>{{ greeting }}</p>

```

## Switching Language in Runtime


## Useful Links

- [Angular Localization Documentation](https://angular.io/guide/i18n)
- [ICU Syntax Documentation](https://unicode-org.github.io/icu/userguide/format_parse/messages/)
