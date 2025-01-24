# Claw2Performance

This project was generated with [Angular CLI](https://github.com/angular/angular-cli) version 17.0.0.

## Specific To `Localize`
Since localize replaces translation values at compile time, reading from the JSON file versus hardcoding values in the HTML shouldn’t make a difference. However, to ensure consistency and avoid potential discrepancies, I set the default language to Farsi. This forces English values to be explicitly read from the JSON file for comparison purposes, ensuring we’re comparing apples to apples.

Running `ng serve` will serve the application in Polish. To serve it in English, use the following command: `ng serve --configuration=en-US`


### Runtime Translation Limitation
Unlike libraries such as `ngx-translate` and `Transloco`, which support dynamic runtime translations through features like the `| translate` pipe, `localize` does not natively provide strong support for runtime/dynamic translations. For scenarios like translating keys dynamically in an `ngFor` loop based on a label value, I had to use a workaround to dynamically resolve the translation key.

Here’s an example of how I achieved this:

```typescript
  readonly LABELS: Record<string, string> = {
    'stats.totalUsers': $localize`:@@stats.totalUsers:Total Users`,
    'stats.activeSessions': $localize`:@@stats.activeSessions:Active Sessions`,
    'stats.responseTime': $localize`:@@stats.responseTime:Response Time`,
    'stats.totalRevenue': $localize`:@@stats.totalRevenue:Total Revenue`,
    'stats.date': $localize`:@@stats.date:Date`,

    /// rest of the keys

    getTranslatedLabel(labelKey: string): string {
      return this.LABELS[labelKey] ?? labelKey;
  }
  };
``` 

```HTML
  <tr *ngFor="let item of stats">
    <td>{{ getTranslatedLabel(item.label) }}</td>
    <td>{{ item.value }}</td>
  </tr>
```

## Development server

Run `ng serve` for a dev server. Navigate to `http://localhost:4200/`. The application will automatically reload if you change any of the source files.

## Code scaffolding

Run `ng generate component component-name` to generate a new component. You can also use `ng generate directive|pipe|service|class|guard|interface|enum|module`.

## Build

Run `ng build` to build the project. The build artifacts will be stored in the `dist/` directory.

## Running unit tests

Run `ng test` to execute the unit tests via [Karma](https://karma-runner.github.io).

## Running end-to-end tests

Run `ng e2e` to execute the end-to-end tests via a platform of your choice. To use this command, you need to first add a package that implements end-to-end testing capabilities.

## Further help

To get more help on the Angular CLI use `ng help` or go check out the [Angular CLI Overview and Command Reference](https://angular.io/cli) page.
