

## 1. Setup
Install-Module -Name Pester -Scope CurrentUser -Force
Import-Module Pester 

Ensure Test names use the format {testName}.Tests.ps1. This allow VS Code extensions
to recognize that these are tests, which provides integration abilities such as
selecting tests to run from the editor.


## 2 Pester Caveats

- Dependency injection not supported in Powershell.
- Constant restarting of Powershell sessions is necessary in order to pickup changes in modules (code under test).
Otherwise tests are running on cached changes.