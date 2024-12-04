    # Architecture Decision Record (ADR) Process

  **Objective**: Formalize the process of documenting architectural decisions.

  ## Details:
  - Context and problem statement driving the decision.
  - The decision made and its scope.
  - PoCs or experiments conducted to validate the decision.
  - Consideration of licensing models and costs.
  - Evaluation of maintainability and extensibility of the solution.
  - References to supporting documentation or discussions.

  **Reference:**
  - [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
  
  # Review In-House Libraries and Determine Future Roadmap

  **Objective:** Assess and plan the future of our in-house libraries to align with company goals.

  **Libraries to Review:**
  - **Bct.Common.Logging**: Custom logging library.
  - **Bct.Common.Claw**: Localization library.
  - **Bct.Common.DataAccess**: Data access ORM.
  - **Bct.Common.MessageBus**: Messaging abstraction.
  - **Bct.Common.Host**: Dependency Injection wrapper.
  - **Bct.Dc.Api**: MQTT handling library.
  - **Bct.Common.GuiShell**: UI shell supporting MFE architecture.
  - **Bct.WebApi.Gateway**: Gateway/Router/Identity Provider

  # Research Alternatives to NServiceBus

  **Objective:** Identify messaging frameworks with better licensing terms and cost benefits.
  **Methodology:** Follow established ADR methodology.

  **Potential Alternatives:**
  - **Rebus**
  - **MassTransit**
  - **RabbitMQ.NET**
  - **ZeroMQ**

  # Revamp Internal Onboarding & Learning Materials

  **Objective:** Modernize onboarding materials by transitioning from SharePoint to markdown documents inside a centralized repository

  **Areas to Update:**
  - Approaches to modernization and simplification.
  - Git Flow strategy.
  - Recommended libraries.
  - Ports & Adapters training.

  # Establish Documentation Standards

  **Objective:** Standardize project documentation for consistency and clarity.

  **Deliverables:**
  - **README.md Template**
  - **DEBUGGING.md** Guidelines
  - **TESTING.md** Guidelines

  # Develop Performance and Security Standards

  **Objective:** Define and implement standards for application performance measuring and security practices.

  **Actions:**
  - Go over benchmarking libraries and select and document its usage
  - Select appropriate tooling for monitoring and enforcement.



  # Create Teams Group for Architectural Communication

  **Objective:** Enhance communication among architects and tech leads via a dedicated Teams group.

  # Establish Recurring Architectural Meetings

  **Objective:** Schedule regular meetings for architectural discussions and updates.

  # Organize Monthly Architectural Brown Bag Sessions

  **Objective:** Foster a culture of learning and increase buy-in through monthly knowledge-sharing sessions.

  **Benefits:**
  - Encourage collaboration.
  - Promote innovation.
  - Support professional development.
