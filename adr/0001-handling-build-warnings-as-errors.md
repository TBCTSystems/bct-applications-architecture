# Handling Build Warnings as Errors in .NET Projects

* Status: accepted
* Deciders: BCT Architecture Team
* Date: 2025-03-07
* Technical Story: [EPM-12597](https://terumobct.atlassian.net/browse/EPM-12597)

## Context and Problem Statement

The development team needs to establish a clear policy regarding the treatment of compiler warnings as errors in .NET projects across Terumo BCT. Initially, there was a goal to achieve builds with zero warnings to improve code quality and maintainability. However, practical implementation challenges have led to the need for a more flexible approach.

## Decision Drivers

* Code quality and maintainability requirements
* Impact on development velocity and team productivity
* Existing codebase with legacy warnings
* Need for practical and sustainable implementation
* Balance between strict quality standards and development efficiency

## Considered Options

* Option 1: Strict Enforcement (TreatWarningsAsErrors = true)
* Option 2: Flexible Warning Management (Allow teams to manage warnings)

## Decision Outcome

Chosen option: "Flexible Warning Management", because it provides a balanced approach that maintains development velocity while encouraging good practices.

Key points of the decision:
* Projects are allowed to turn off the TreatWarningsAsErrors build option
* Teams are advised to keep warnings to an absolute minimum
* Warning management becomes a team responsibility rather than a strict enforcement

### Positive Consequences

* Maintains development velocity by preventing blocking builds due to warnings
* Provides teams flexibility to handle legacy code and special cases
* Allows for gradual improvement rather than enforcing immediate perfection
* Reduces immediate impact on existing projects

### Negative Consequences

* Risk of warning accumulation over time if not properly managed
* Potential inconsistency in warning handling across different projects
* May require additional code review attention to prevent warning proliferation

## Pros and Cons of the Options

### Strict Enforcement

* Good, because it enforces high code quality standards
* Good, because it prevents warning accumulation
* Good, because it ensures all code meets the same quality bar
* Bad, because it can significantly impact development velocity
* Bad, because it may require substantial effort to fix existing warnings
* Bad, because it might lead to quick fixes rather than proper solutions

### Flexible Warning Management

* Good, because it maintains development velocity
* Good, because it allows teams to manage their own quality trade-offs
* Good, because it provides flexibility for legacy code
* Bad, because it might lead to warning accumulation if not managed well
* Bad, because it requires more discipline from development teams
* Bad, because it could result in inconsistent practices across teams

## Links

* [EPM-12597](https://terumobct.atlassian.net/browse/EPM-12597) - Original EPIC discussing the treatment of warnings as errors