export default {
  agents: [
    {
      id: 'protocol-architect',
      name: 'Protocol Architect',
      description:
        'Analyzes specifications, researches ACME and EST, and produces the authoritative architectural decision record for both PoCs.',
      promptPath: 'prompts/main/protocol-architect.md'
    },
    {
      id: 'poc-orchestrator',
      name: 'PoC Orchestrator',
      description:
        'Consumes the ADR and specifications to decompose work, delegate to specialists, and ensure each development step is scribed before and after execution.',
      promptPath: 'prompts/main/poc-orchestrator.md'
    },
    {
      id: 'qa-steward',
      name: 'QA Steward',
      description:
        'Validates generated artifacts against the ADR and specifications, recording test outcomes that drive the quality gate.',
      promptPath: 'prompts/main/qa-steward.md'
    },
    {
      id: 'final-packager',
      name: 'Final Packager',
      description:
        'Compiles final deliverables, including the PoC README and references to the coaching log for reproducibility.',
      promptPath: 'prompts/main/final-packager.md'
    }
  ]
};
