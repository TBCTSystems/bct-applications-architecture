

## 1. Setup
Install-Module -Name Pester -Scope CurrentUser -Force
Import-Module Pester 


## 2. Powershell vs C#
- Dependency injection not supported in Powershell.
- Constant restarting of Powershell sessions is necessary in order to pickup changes.
Otherwise tests are running on cached changes.