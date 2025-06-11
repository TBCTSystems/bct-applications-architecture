# Architectural Decision on Package Versioning Strategy

* Status: Proposed
* Deciders: BCT Architecture Team
* Date: 2025-06-10

## Context and Problem Statement

As we integrate various packages into our projects, we must decide on a versioning strategy that balances stability and flexibility. The problem is determining the appropriate approach to version management for our dependencies, specifically whether to adopt floating versions for patches/minors or to utilize strict versions.

## Decision Drivers

* Stability of the application
* Frequency of package updates
* Team's agility to handle breaking changes
* Maintenance overhead in updates

## Considered Options

* Use floating version for patch version (e.g., 1.3.*)
* Use floating version for minor version (e.g., 1.*)
* Use strict version (e.g., 1.3.9)

## Decision Outcome

Chosen option: ...

### Positive Consequences

* **Stability:** Ensures a stable and predictable environment, reducing the risk of unexpected failures or runtime errors due to dependency updates.
* **Compatibility:** Guarantees that the application behaves consistently as it relies on known and tested versions of dependencies, minimizing integration issues.
* **Environment Replication:** Facilitates easier replication of development, testing, and production environments, allowing the team to troubleshoot issues more efficiently.
* **Controlled Upgrades:** Allows the team to control upgrades, ensuring that any updates are deliberate and tested for compatibility.

### Negative Consequences

* **Lack of Updates:** Increases the likelihood of missing out on important bug fixes, performance improvements, and security patches that come with newer versions.
* **Maintenance Overhead:** Requires more manual effort to review and update dependencies periodically, which can lead to technical debt if not managed properly.
* **Slower Adoption of Features:** May delay the integration of new features and enhancements from upstream libraries, potentially hindering the development process.

## Pros and Cons of the Options

### Floating version for patch version (1.3.*)

* Good because it allows for automatic incorporation of bug fixes and security patches without changing the minor version.
* Good because it minimizes disruption to the development and operation teams while still allowing for some flexibility.
* Bad because multiple libraries may depend on different floating versions of the same package, leading to version conflicts. Legacy configurations that contain hard-coded bindings can further complicate this scenario, making dependency resolution challenging.
* Bad because minor updates could introduce unforeseen bugs or compatibility issues, leading to possible runtime errors.
* Bad because due to human factor sometimes breaking changes are introduced in a new patch and this completely stops development in the repository until it is fixed - We have seen examples of such changes for both Terumo packages and external products.
* Bad because legacy projects with specific assembly bindings in `web.config` may encounter conflicts if floating versions introduce incompatible updates. This can result in runtime errors or application failures.

### Floating version for minor version (1.*)

* Good because it maximizes flexibility and allows for adoption of new features without the need for frequent updates.
* Good because it can foster innovation by easily incorporating new functionalities from upstream dependencies.
* Bad because multiple libraries may depend on different floating versions of the same package, leading to version conflicts. Legacy configurations that contain hard-coded bindings can further complicate this scenario, making dependency resolution challenging.
* Bad because it increases the risk of breaking changes significantly, as major updates can introduce issues that the team might not be prepared to handle immediately.
* Bad because legacy projects with specific assembly bindings in `web.config` may encounter conflicts if floating versions introduce incompatible updates. This can result in runtime errors or application failures.

### Strict version (1.3.9)

* Good because it provides maximum stability and predictability in the development environment, thereby reducing the risk of unexpected failure due to breaking changes.
* Good because the entire team can replicate the same environment, ensuring consistency across development, testing, and production.
* Bad because it can lead to stagnation if packages are not updated regularly, missing out on improvements such as performance enhancements and security patches.