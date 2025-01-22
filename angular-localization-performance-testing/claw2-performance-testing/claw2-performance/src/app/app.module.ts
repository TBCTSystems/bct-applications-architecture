import { NgModule, ErrorHandler } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { HttpClientModule } from '@angular/common/http';
import { BctTranslationModule, BctTranslationService, DEFAULT_LANGUAGE_REQUIRED, ERROR_ON_EMPTY_DATASET } from 'bct-applications-platform-translation';
import { AppComponent } from './app.component';
import { WebVitalsService } from './performance/web-vitals.service';

@NgModule({
  declarations: [AppComponent],
  imports: [
    BrowserModule,
    HttpClientModule,
    BctTranslationModule.forRoot({
      resourceUrl: 'assets/i18n/'
    })
  ],
  providers: [
    BctTranslationService,
    WebVitalsService,
    {
      provide: DEFAULT_LANGUAGE_REQUIRED,
      useValue: true
    },
    {
      provide: ERROR_ON_EMPTY_DATASET,
      useValue: true
    }
  ],
  bootstrap: [AppComponent]
})
export class AppModule { }
