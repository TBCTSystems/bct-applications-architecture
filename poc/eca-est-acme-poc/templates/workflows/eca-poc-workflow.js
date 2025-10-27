import { resolveStep, resolveModule } from './utils.js';

const defaultStepConfig = {
  engine: 'claude',
  model: 'sonnet'
};

const highReasoningOverrides = {
  model: 'opus',
  modelReasoningEffort: 'high'
};

export default {
  name: 'ECA Proof of Concept Workflow',
  steps: [
    resolveStep('protocol-architect', {
      ...defaultStepConfig,
      ...highReasoningOverrides,
      executeOnce: true
    }),
    resolveStep('poc-orchestrator', {
      ...defaultStepConfig,
      agentName: 'ACME Orchestrator'
    }),
    resolveStep('qa-steward', {
      ...defaultStepConfig,
      ...highReasoningOverrides,
      agentName: 'ACME QA'
    }),
    resolveModule('quality-gate', {
      ...defaultStepConfig,
      model: 'haiku'
    }),
    resolveStep('poc-orchestrator', {
      ...defaultStepConfig,
      agentName: 'EST Orchestrator'
    }),
    resolveStep('qa-steward', {
      ...defaultStepConfig,
      ...highReasoningOverrides,
      agentName: 'EST QA'
    }),
    resolveModule('quality-gate', {
      ...defaultStepConfig,
      model: 'haiku'
    }),
    resolveStep('final-packager', {
      ...defaultStepConfig
    })
  ],
  subAgentIds: [
    'coaching-scribe',
    'powershell-dev',
    'docker-expert',
    'pester-tester'
  ]
};
