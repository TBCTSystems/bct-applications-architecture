# Lumia 2.0 Internationalization (i18n) Implementation Epic

## Overview
This epic implements comprehensive i18n support across Lumia 2.0 by:
1. Replacing CLAW2 with Angular Transloco for dynamic language handling
2. Developing a dedicated Internationalization Service (.NET 8) for centralized culture management
3. Enhancing Security Service integration for JWT claim-based localization
4. Establishing standardized processes for language pack deployment

## Core Components

### 1. Transloco Framework Integration
- **Custom Loader Package (@bct/transloco-i18n-loader)**
  - Dynamic API-driven language loading
  - JWT claim synchronization
  - Culture metadata injection
- **CLAW2 Migration**
  - Automated resource conversion utility (.NET Global Tool)
  - Template syntax migration: `translateLabel` → `transloco`
  - Modular translation file structure

### 2. Internationalization Service
- **Key APIs**
  - `GET /languages/{code}` - Merged translations from MinIO
  - `POST /user/culture` - Regional settings management
  - Admin endpoints for language pack CRUD
- **Storage Architecture**
  - MinIO: `i18n/` bucket with `[module]_[lang].json` structure
  - SQL Server: User preferences and format templates
- **Response Caching**
  - 5-minute cache for merged translations
  - Automatic invalidation on pack updates

### 3. Security Service Modifications
- **JWT Claim Enhancements**
  - `preferred_culture`: En-US|Fr-FR|etc
  - `culture_settings`: Serialized regional preferences
- **Token Lifecycle Integration**
  - Culture resolution during authentication
  - Claims refresh on settings changes
  - Fallback to browser headers

## Technical Requirements
| Component | Specification |
|-----------|---------------|
| Frontend | Angular 15+, Transloco 6.x |
| Backend | .NET 8, EF Core 8, MinIO RELEASE.2024-02-04 |
| Security | OpenIdDict 4.0 with claim destinations |
| CI/CD | Migration scripts for CLAW2 conversion |

## Dependencies
1. **Frontend**
   - Transloco loader integration
   - Culture selector UI components
2. **Backend**
   - Internationalization Service development
   - MinIO/SQL Server provisioning
3. **Security Team**
   - JWT claim management
   - OAuth2 culture resolution flow

## Reference Documentation
- Full architecture: [i18n.md](./i18n.md)
- Sequence diagrams (§3.1-3.3)
- ERD for culture settings (§2.2.2)
- API specifications (§2.2.3)
