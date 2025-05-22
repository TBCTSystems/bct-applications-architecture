# Use `curl` for HTTP(S) requests in scripting

* Status: Proposed
* Deciders: BCT Software Team
* Date: 2025-05-22

## Context and Problem Statement

Our organization utilizes scripting for various tasks, many of which involve making HTTP(S) requests.
Currently, there isn't a standardized approach, leading to the use of both `curl` and `Invoke-WebRequest` (PowerShell).
This lack of standardization can lead to inconsistencies, increased learning curve for developers switching between script types, and challenges in maintaining scripts across different environments (Windows, Linux, Docker).
The question is: Which command-line tool should be the standard for making HTTP(S) requests in our scripts to ensure consistency, portability, and maintainability?

## Decision Drivers

* Cross-platform compatibility (Windows, Linux, macOS, Docker).
* Simplicity and conciseness of script syntax.
* Ease of reuse in various environments (e.g., Dockerfiles, CI/CD pipelines).
* Leveraging existing team familiarity and skillset.
* Performance considerations for common scripting tasks.
* Maintainability and readability of scripts.

## Considered Options

* **Option 1: `curl`**: Utilize `curl` as the standard tool for HTTP(S) requests in all new and updated scripts.
* **Option 2: `Invoke-WebRequest`**: Utilize PowerShell's `Invoke-WebRequest` cmdlet as the standard.
* **Option 3: Allow both (No change)**: Continue allowing developers to choose either tool based on preference or script environment.

## Decision Outcome

Proposed option: "**Option 1: `curl`**", because it best addresses the key decision drivers, particularly cross-platform compatibility, reusability, and simpler syntax for common scripting scenarios.

### Positive Consequences

* Improved script portability across different operating systems and container environments.
* Simplified and more consistent scripting practices.
* Reduced learning curve for developers working on different scripts.
* Enhanced reusability of script snippets in Dockerfiles and CI/CD pipelines.
* Leverages widespread availability and community support for `curl`.

### Negative Consequences

* Scripts requiring deep integration with PowerShell's object pipeline for HTTP responses might need workarounds or might still opt for `Invoke-WebRequest` in specific, justified cases (to be documented as exceptions).
* Developers primarily working in PowerShell might have a slight learning curve if unfamiliar with `curl`'s syntax for advanced use cases.

## Pros and Cons of the Options

### `curl`

* Good, because it is ubiquitous across platforms (Windows, Linux, macOS).
* Good, because it offers generally simpler and more concise syntax for common requests.
* Good, because it is excellent for direct use in Dockerfiles and shell scripts.
* Good, because it has a large community, extensive documentation, and proven reliability.
* Good, because it is lightweight and often performant for basic tasks.
* Bad, because its output is text-based; requires parsing for complex data (e.g., JSON, XML) if not piped to tools like `jq`.
* Bad, because it has less direct integration with PowerShell objects and pipeline if that is a primary requirement.

### `Invoke-WebRequest`

* Good, because it is native to PowerShell, offering excellent integration with PowerShell pipeline and objects.
* Good, because it parses responses (HTML, JSON) into objects automatically.
* Good, because it handles session management, credentials, and web forms in a PowerShell-idiomatic way.
* Bad, because it is primarily Windows/PowerShell specific, limiting cross-platform script portability.
* Bad, because it can be more verbose for simple GET/POST requests.
* Bad, because it is less straightforward to use directly in non-PowerShell environments like standard Dockerfiles or Linux shell scripts.

### Allow both (No change)

* Good, because it offers maximum flexibility for developers.
* Good, because there is no immediate effort to change existing scripts.
* Bad, because it leads to inconsistencies and fragmentation in scripting practices.
* Bad, because it increases cognitive load for developers needing to understand both tools.
* Bad, because it hinders script portability and reusability across different platforms and environments.
* Bad, because it makes standardization of error handling and logging more complex.

## Links

* [Official `curl` Documentation](https://curl.se/docs/httpscripting.html)
* [Microsoft `Invoke-WebRequest` Documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.5)
* [Relevant StackOverflow Discussion](https://stackoverflow.com/questions/47364244/curl-vs-invoke-webrequest)
* [Difference between cURL and Invoke-WebRequest](https://stackoverflow.com/questions/78900590/difference-in-behavior-between-curl-and-invoke-webrequest-for-authorization-head)