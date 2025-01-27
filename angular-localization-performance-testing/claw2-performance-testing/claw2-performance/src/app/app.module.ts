import { NgModule, ErrorHandler } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { HttpClientModule } from '@angular/common/http';
import { HttpClient } from '@angular/common/http';
import { TranslocoModule, TRANSLOCO_CONFIG, translocoConfig, TRANSLOCO_LOADER, 
  TRANSLOCO_TRANSPILER, DefaultTranspiler, 
  TRANSLOCO_MISSING_HANDLER, DefaultMissingHandler, 
  TRANSLOCO_INTERCEPTOR, DefaultInterceptor,
  DefaultFallbackStrategy, TRANSLOCO_FALLBACK_STRATEGY 
} from '@jsverse/transloco';
import { TranslocoLocaleModule, provideTranslocoLocale } from '@jsverse/transloco-locale';
import { Injectable } from '@angular/core';

import { AppComponent } from './app.component';
import { WebVitalsService } from './performance/web-vitals.service';

@Injectable({ providedIn: 'root' })
export class TranslocoHttpLoader {
  constructor(private http: HttpClient) {}
  getTranslation(lang: string) {
    return this.http.get(`/assets/i18n/${lang}.json`);
  }
}

@NgModule({
  declarations: [AppComponent],
  imports: [
    BrowserModule,
    HttpClientModule,
    TranslocoModule,
    TranslocoLocaleModule,
  ],
  providers: [
    {
      provide: TRANSLOCO_CONFIG,
      useValue: translocoConfig({
        availableLangs: ['en-US', 'en-GB', 'es-ES', 'zh-CN'],
        defaultLang: 'en-US',
        fallbackLang: 'en-US', // Use English as fallback
        reRenderOnLangChange: true,
        prodMode: true
      })
    },
    { 
      provide: TRANSLOCO_LOADER, 
      useClass: TranslocoHttpLoader 
    },
    {
      provide: TRANSLOCO_TRANSPILER, // Provide the default transpiler
      useClass: DefaultTranspiler
    },
    {
      provide: TRANSLOCO_MISSING_HANDLER, // Use the default missing handler
      useClass: DefaultMissingHandler
    },
    {
      provide: TRANSLOCO_INTERCEPTOR,
      useClass: DefaultInterceptor, // Provide the default interceptor
    },
    {
      provide: TRANSLOCO_FALLBACK_STRATEGY, // Use the default fallback strategy
      useClass: DefaultFallbackStrategy
    },
    provideTranslocoLocale(),
    WebVitalsService,
  ],
  bootstrap: [AppComponent]
})
export class AppModule { }
