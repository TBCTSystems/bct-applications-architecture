import { ApplicationConfig } from '@angular/core';
import { provideRouter } from '@angular/router';
import { BctTranslationModule } from 'bct-applications-platform-translation';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    BctTranslationModule.forRoot({
      resourceUrl: 'assets/i18n'
    }).providers
  ]
};
