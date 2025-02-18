
# Summary of `Transloco` for Angular i18n/l10n

Transloco is a modern, feature-rich, and highly customizable library for handling internationalization (i18n) and localization (l10n) in Angular applications. It supports various advanced features like runtime language switching, lazy-loaded translations, and scoped translations while being lightweight and developer-friendly.

---

## Why Use Transloco?

- **Flexible Architecture**: Allows customization to meet various application needs, including dynamic and static translations.
- **Runtime Language Switching**: Switch languages dynamically without reloading the application.
- **Lazy Loading**: Efficiently loads translations only when needed, reducing the initial app load time.
- **Scoped Translations**: Helps organize translations into modular chunks for better maintainability.
- **Rich Formatting**: Supports interpolation, pluralization, and parameterized translations.
- **Tooling Support**: Provides plugins for managing keys, validating translations, and testing.
- **Performance-Oriented**: Offers caching, on-demand loading, and smaller payloads for improved performance.

---

## Features of Transloco

### 1. Core Functionality
- Define translations in JSON files.
- Easily integrate with Angular templates using pipes.
- Programmatic translation access through a service.

### 2. Language Management
- Set a default language.
- Change the active language dynamically:
  ```typescript
  this.translocoService.setActiveLang('fr');
  ```

### 3. Dynamic Interpolation
- Insert dynamic values into translations:
  ```json
  {
    "greeting": "Hello, {{name}}!"
  }
  ```
- Template usage:
  ```html
  <p>{{ 'greeting' | transloco: { name: 'John' } }}</p>
  ```

### 4. Fallback Languages
- Specify fallback languages for missing translations:
  ```typescript
  TranslocoModule.forRoot({
    defaultLang: 'en',
    fallbackLang: ['fr', 'es']
  });
  ```

### 5. Scoped Translations
- Organize translations by module or feature:
  - Example file structure:
    ```
    src/assets/i18n/home/en.json
    src/assets/i18n/about/en.json
    ```
- Use scoped pipes or services to fetch the correct translations.

### 6. Lazy Loading
- Load translations only when required:
  ```typescript
  TranslocoModule.forRoot({
    loader: {
      provide: TRANSLOCO_LOADER,
      useClass: TranslocoHttpLoader
    }
  });
  ```

### 7. Localization Support
- Handle date, time, and number formatting with the Transloco Locale plugin.

### 8. Advanced Testing
- Use the Transloco Testing plugin to mock translations during unit testing.

---

## Getting Started

### Step 1: Install Transloco
```bash
npm install @ngneat/transloco
```

### Step 2: Add Transloco to Your Project
Run the schematic to set up the configuration:
```bash
ng add @ngneat/transloco
```
This will:
- Create a `transloco.config.js` file.
- Add the `TranslocoRootModule` to your `AppModule`.
- Set up the `i18n` folder with an example translation file.

### Step 3: Configure Transloco
Open `src/app/transloco-root.module.ts` to adjust settings:
```typescript
import { NgModule } from '@angular/core';
import { TranslocoModule, TRANSLOCO_CONFIG, translocoConfig } from '@ngneat/transloco';

@NgModule({
  imports: [TranslocoModule],
  providers: [
    {
      provide: TRANSLOCO_CONFIG,
      useValue: translocoConfig({
        defaultLang: 'en',
        fallbackLang: 'en',
        availableLangs: ['en', 'fr', 'es'],
        prodMode: true,
      }),
    },
  ],
})
export class TranslocoRootModule {}
```

### Step 4: Create Translation Files
Add translation files under the `src/assets/i18n/` folder:

**`en.json`**
```json
{
  "welcome": "Welcome to our application!"
}
```

**`fr.json`**
```json
{
  "welcome": "Bienvenue dans notre application !"
}
```

### Step 5: Use Transloco in Templates
```html
<h1>{{ 'welcome' | transloco }}</h1>
```

---

## Advanced Topics

### Lazy Loading Translations
To load translations via HTTP:
1. Create a loader service:
   ```typescript
   import { Injectable } from '@angular/core';
   import { HttpClient } from '@angular/common/http';
   import { TranslocoLoader } from '@ngneat/transloco';

   @Injectable({ providedIn: 'root' })
   export class TranslocoHttpLoader implements TranslocoLoader {
     constructor(private http: HttpClient) {}
     getTranslation(lang: string) {
       return this.http.get(`/assets/i18n/${lang}.json`);
     }
   }
   ```
2. Register the loader:
   ```typescript
   TranslocoModule.forRoot({
     loader: {
       provide: TRANSLOCO_LOADER,
       useClass: TranslocoHttpLoader
     }
   });
   ```

### Scoped Translations
Use scoped translation for lazy-loaded modules:
```typescript
import { TRANSLOCO_SCOPE } from '@ngneat/transloco';

@NgModule({
  providers: [
    {
      provide: TRANSLOCO_SCOPE,
      useValue: 'home',
    },
  ],
})
export class HomeModule {}
```

---

## Transloco Plugins

- **Transloco Keys Manager**: Automatically extract and manage translation keys.
- **Transloco Locale**: Format dates, numbers, and currencies.
- **Transloco Validator**: Validate your translation files for missing keys.

---

## Best Practices

- **Organize Translation Files**: Group translations by feature or module to improve maintainability.
- **Use Interpolation**: Dynamically pass values to translations to avoid redundancy.
- **Leverage Plugins**: Use plugins like Transloco Keys Manager to streamline translation management.
- **Test Translations**: Use Transloco Testing to ensure translations work as expected.

---

## Comparison with Other Libraries

| Feature                  | Transloco | ngx-translate | Angular i18n |
|--------------------------|-----------|---------------|--------------|
| Lazy Loading             | ✅        | ✅            | ❌           |
| Runtime Language Switch  | ✅        | ✅            | ❌           |
| Scoped Translations      | ✅        | ❌            | ❌           |
| Rich Formatting          | ✅        | Limited       | Limited      |
| Plugins and Tooling      | ✅        | Limited       | ❌           |


Transloco is an excellent choice for Angular applications that require robust and scalable i18n/l10n solutions.

## Links
[Rika Programs Branch](https://github.com/TBCTSystems/bct-rika-programs/tree/poc/bxl/EPM-26696)