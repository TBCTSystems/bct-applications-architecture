# Project Configuration for `@angular/localize`

## Install the Localize Package

```bash
ng add @angular/localize
```

## Configuration in `angular.json`

```json
{
  "$schema": "./node_modules/@angular/cli/lib/config/schema.json",
  "version": 1,
  "newProjectRoot": "projects",
  "projects": {
    "angular-localization": {
      "i18n": {  // Localization configuration
        "sourceLocale": "en-US",  // Defines the source (default) locale of the app
        "locales": {  // Specifies the available translations
          "fa": "src/locale/messages.fa.json",  // Farsi translation file
          "ja": "src/locale/messages.ja.json"   // Japanese translation file
        }
      },
      "projectType": "application",
      "schematics": {
        "@schematics/angular:component": {
          "standalone": false
        },
        "@schematics/angular:directive": {
          "standalone": false
        },
        "@schematics/angular:pipe": {
          "standalone": false
        }
      },
      "root": "",
      "sourceRoot": "src",
      "prefix": "app",
      "architect": {
        "build": {
          "builder": "@angular-devkit/build-angular:application",
          "options": {
            "localize": false,  // Enables build-time localization
            "outputPath": "dist/angular-localization",
            "index": "src/index.html",
            "browser": "src/main.ts",
            "polyfills": [
              "zone.js",
              "@angular/localize/init"  // Initializes Angular localization (added automatically)
            ],
            "tsConfig": "tsconfig.app.json",
            "assets": [
              {
                "glob": "**/*",
                "input": "public"
              }
            ],
            "styles": [
              "src/styles.css"
            ],
            "scripts": []
          },
          "configurations": {
            "production": {
              "budgets": [
                {
                  "type": "initial",
                  "maximumWarning": "500kB",
                  "maximumError": "1MB"
                },
                {
                  "type": "anyComponentStyle",
                  "maximumWarning": "4kB",
                  "maximumError": "8kB"
                }
              ],
              "outputHashing": "all"
            },
            "development": {
              "localize": false,  // Disables localization in development mode for faster builds
              "optimization": false,
              "extractLicenses": false,
              "sourceMap": true
            },
            "fa": {
              "localize": ["fa"]  // Build configuration for Farsi locale
            },
            "ja": {
              "localize": ["ja"]  // Build configuration for Japanese locale
            }
          },
          "defaultConfiguration": "production"
        },
        "serve": {
          "builder": "@angular-devkit/build-angular:dev-server",
          "configurations": {
            "production": {
              "buildTarget": "angular-localization:build:production"
            },
            "fa": { // serve configuration for fa
              "buildTarget": "angular-localization:build:fa"
            },
            "ja": { // serve configuration for ja
              "buildTarget": "angular-localization:build:ja"
            }
            "development": {
              "buildTarget": "angular-localization:build:development"
            }
          },
          "defaultConfiguration": "development"
        },
        "extract-i18n": {
          "builder": "@angular-devkit/build-angular:extract-i18n",
          "options": {
            "buildTarget": "angular-localization:build",  // Build target for extracting translations
            "outputPath": "src/locale"  // Directory to store extracted translation files
          }
        },
        "test": {
          "builder": "@angular-devkit/build-angular:karma",
          "options": {
            "polyfills": [
              "zone.js",
              "zone.js/testing",
              "@angular/localize/init"
            ],
            "tsConfig": "tsconfig.spec.json",
            "assets": [
              {
                "glob": "**/*",
                "input": "public"
              }
            ],
            "styles": [
              "src/styles.css"
            ],
            "scripts": []
          }
        }
      }
    }
  }
}
```

### **The `i18n` Section**

The `i18n` section defines the source locale (**default language**) and available translations for the project.

```json
"i18n": {
  "sourceLocale": "en-US",
  "locales": {
    "fa": "src/locale/messages.fa.json",
    "ja": "src/locale/messages.ja.json"
  }
}
```

- **`sourceLocale`**: Specifies the application's default language (`en-US` in this case).
- **`locales`**: Lists the available translation files for different languages.
    - `fa`: Refers to the Farsi translation file located at `src/locale/messages.fa.json`.
    - `ja`: Refers to the Japanese translation file located at `src/locale/messages.ja.json`.

### **`build.options.localize`**

This option enables **build-time localization**. When set to `true`, Angular generates separate output bundles for each specified locale.

```json
"localize": true
```

- When building the application (`ng build --localize`), Angular creates localized versions of the app for each locale listed in the `i18n` section.
- This allows serving users a version of the app in their preferred language.

### **`build.configurations`**

This section defines specific build configurations for different environments and locales.

```json
"configurations": {
  "production": {
    "outputHashing": "all"
  },
  "development": {
    "localize": false,
    "optimization": false,
    "extractLicenses": false,
    "sourceMap": true
  },
  "fa": {
    "localize": ["fa"]
  },
  "ja": {
    "localize": ["ja"]
  }
}
```

- **`development`**: Configuration for development builds. Localization is disabled (`localize: false`) to speed up the development process.
- **`fa`**: Configuration for building the app specifically for the Farsi locale.
    - Command: `ng build --configuration=fa`
- **`ja`**: Configuration for building the app specifically for the Japanese locale.
    - Command: `ng build --configuration=ja`

### **`serve.configurations`**

This section defines how the application should serve different environments and locales.

```json
"serve": {
  "builder": "@angular-devkit/build-angular:dev-server",
  "configurations": {
    "production": {
      "buildTarget": "angular-localization:build:production"
    },
    "development": {
      "buildTarget": "angular-localization:build:development"
    },
    "fa": {
      "buildTarget": "angular-localization:build:fa"
    },
    "ja": {
      "buildTarget": "angular-localization:build:ja"
    }
  },
  "defaultConfiguration": "development"
},
```

To add serve configurations for locales:

```json
"fa": {
  "buildTarget": "angular-localization:build:fa"
},
"ja": {
  "buildTarget": "angular-localization:build:ja"
}
```

- **Command to serve Farsi version**: `ng serve --configuration=fa`
- **Command to serve Japanese version**: `ng serve --configuration=ja`

### **`extract-i18n`**

This section configures the extraction of translatable messages from the source code into translation files.

```json
"extract-i18n": {
  "builder": "@angular-devkit/build-angular:extract-i18n",
  "options": {
    "buildTarget": "angular-localization:build",
    "outputPath": "src/locale"
  }
}
```

- **`buildTarget`**: Specifies which build configuration should be used when extracting translations.
- **`outputPath`**: Defines where the extracted translation files will be saved (e.g., `src/locale/messages.xlf`).

Command to Extract Translations:

```powershell
ng extract-i18n
```

This command generates a translation file (e.g., `messages.xlf`) in the specified output path (`src/locale`).

### Generate Messages Files

Use the following (note that if `"outputPath": "src/locale"` is not added to `angular.json`, we also should pass the output location in the command):

```powershell
ng extract-i18n --format json
```

It creates the message file for the default locale under the specified path. It should be copied for every locale that we want to support, such as `messages.ja.json`.

### Summary

| **Configuration** | **Purpose** |
| --- | --- |
| `i18n` | Defines the default locale and available translations. |
| `build.options.localize` | Enables build-time localization to create separate builds for each language. |
| `build.configurations` | Specifies different build configurations for production, development, and specific locales. |
| `serve.configurations` | Specifies how to serve the app for different environments and locales. |
| `extract-i18n` | Configures the extraction of translatable text into translation files. |

## Configure the Code

### Traditional: `app-module.ts`

```tsx
import { NgModule, LOCALE_ID } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { AppComponent } from './app.component';
import { registerLocaleData } from '@angular/common';

@NgModule({
  declarations: [AppComponent],
  imports: [BrowserModule],
  providers: [
    { provide: LOCALE_ID, useValue: 'en-US' } // Change to 'fa' or 'ja' as needed
  ],
  bootstrap: [AppComponent]
})
export class AppModule {}

```

### Standalone:`main.ts`

```tsx
import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app/app.component';
import { provideRouter } from '@angular/router';
import { provideLocale, LOCALE_ID } from '@angular/core';
import { registerLocaleData } from '@angular/common';

registerLocaleData(localeFa,
bootstrapApplication(AppComponent, {
  providers: [
    provideRouter([]),
    provideLocale(),
    { provide: LOCALE_ID, useValue: 'fa' } // Default to Persian locale
  ]
}).catch(err => console.error(err));

```