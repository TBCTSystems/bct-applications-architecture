# @bct/transloco-i18n-loader

A custom Transloco loader for seamless integration with Lumia Base Platform's Internationalization Service.

## Installation
```bash
npm install @bct/transloco-i18n-loader
```

## Usage

### Basic Configuration
```typescript
import { BctTranslocoI18nModule, I18nConfig } from '@bct/transloco-i18n-loader';

@NgModule({
  imports: [
    TranslocoModule,
    HttpClientModule,
    BctTranslocoI18nModule.forRoot({
      apiUrl: 'https://api.lumia-base/i18n', // Internationalization Service endpoint
      defaultCulture: 'en-US',
      cacheTimeout: 300 // 5 minutes
    })
  ],
  providers: [
    { provide: TRANSLOCO_LOADER, useClass: I18nLoader }
  ]
})
export class AppModule {}
```

## Configuration Options

### I18nConfig Interface
```typescript
interface I18nConfig {
  /** Required API endpoint for Internationalization Service */
  apiUrl: string;
  
  /** Default culture code (falls back to 'en-US') */
  defaultCulture?: string;
  
  /** Translation cache timeout in seconds (default: 300) */
  cacheTimeout?: number;
}
```

## API

### Culture Settings
```typescript
interface CultureSettings {
  preferredLanguage: string;
  regionalSettings: {
    dateFormat: string;
    timeFormat: string;
    numberFormat: {
      decimalSeparator: string;
      groupSeparator: string;
      currency: string;
    };
  };
}
```

### Accessing Culture Settings
In your components:
```typescript
constructor(private translocoService: TranslocoService) {}

get cultureSettings() {
  return this.translocoService.getTranslation(this.translocoService.getActiveLang()).pipe(
    map(translation => translation._culture)
  );
}
```

## Features

- Automatic culture settings injection into translations
- Lazy-loaded language packs
- Built-in caching mechanism
- Seamless integration with JWT claims
- Type-safe culture settings interface

## Error Handling

The loader implements automatic retry logic for:
- Network errors (3 retries with exponential backoff)
- 404 errors (falls back to default culture)
- Invalid translation formats

## Contributing

1. Clone repository
2. Install dependencies: `npm ci`
3. Build package: `npm run build`
4. Run tests: `npm test`

## License
MIT © BCT
