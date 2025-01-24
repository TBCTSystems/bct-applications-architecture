import { TranslateLoader } from '@ngx-translate/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Injectable } from '@angular/core';

@Injectable()
export class CustomTranslateLoader implements TranslateLoader {
    constructor(private http: HttpClient) { }

    public getTranslation(lang: string): Observable<any> {
        return this.http.get(`assets/i18n/${lang}.json`);
    }
}

export function HttpLoaderFactory(http: HttpClient): TranslateLoader {
    return new CustomTranslateLoader(http);
}
