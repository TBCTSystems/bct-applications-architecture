export default {
  agents: [
    {
      id: 'coaching-scribe',
      name: 'Coaching Scribe',
      description:
        'Maintains a narrative build log by capturing the intent, actions, and rationale surrounding each workflow step.',
      promptPath: 'prompts/sub/coaching-scribe.md'
    },
    {
      id: 'powershell-dev',
      name: 'PowerShell Developer',
      description:
        'Implements modular PowerShell for ACME and EST agents, coordinating with the scribe to explain design decisions.',
      promptPath: 'prompts/sub/powershell-dev.md'
    },
    {
      id: 'docker-expert',
      name: 'Docker Expert',
      description:
        'Designs Dockerfiles and compose definitions for the PoC environment, documenting infrastructure choices via the scribe.',
      promptPath: 'prompts/sub/docker-expert.md'
    },
    {
      id: 'pester-tester',
      name: 'Pester Test Writer',
      description:
        'Authors Pester suites that exercise the PowerShell modules and ensures testing intent is captured through the scribe.',
      promptPath: 'prompts/sub/pester-tester.md'
    }
  ]
};
