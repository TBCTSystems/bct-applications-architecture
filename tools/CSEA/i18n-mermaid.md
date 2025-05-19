## Sequences

sequenceDiagram
    participant U as User
    participant F as Angular App (Frontend)
    participant S as Security Service
    participant I as Internationalization Service
    participant DB as SQL Server
    participant M as MinIO

    Note over U,F: Core User Culture Sequence
    rect rgb(242, 242, 242)
        U->>+S: Login (username/password)
        S->>+I: GetUserCultureSettings(userId)
        I->>+DB: Query culture preferences
        DB-->>-I: Return culture data
        I-->>-S: Culture settings response
        S->>S: Generate JWT with culture claims
        S-->>-U: Return authenticated JWT
    end

    Note over U,F: Culture Settings Change Flow
    rect rgb(230, 255, 230)
        U->>+F: Select new culture/format in UI
        F->>+I: PUT /api/user/culture
        I->>+DB: Update user culture settings
        DB-->>-I: Update confirmation
        I->>+S: Notify culture change (userId)
        S-->>-I: Acknowledge
        I-->>-F: 204 No Content
        F->>F: Update Transloco service
        F-->>-U: Show confirmation & reload JWT
    end

    Note over F,I: Language Pack Loading
    rect rgb(230, 230, 255)
        F->>+I: GET /languages/{cultureCode}
        I->>+M: Get language pack file
        M-->>-I: Return .json file
        I-->>-F: Return language pack
        F->>F: Initialize Transloco with pack
    end

    Note over F,I: Admin Pack Management
    rect rgb(255, 230, 230)
        U->>+F: Admin uploads new language pack
        F->>+I: POST /api/admin/packs
        I->>+M: Store .json file
        M-->>-I: Storage confirmation
        I->>+DB: Update available languages
        DB-->>-I: Update confirmation
        I-->>-F: 201 Created
        F-->>-U: Show success notification
    end

