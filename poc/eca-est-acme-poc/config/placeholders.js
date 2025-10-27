// Paths within the user's CodeMachine workspace that this workflow relies on.
export const userDir = {
  specifications: '.codemachine/inputs/specifications.md',
  architecture_decision_record: '.codemachine/artifacts/architecture/adr.md',
  coaching_log: '.codemachine/artifacts/logs/coaching_log.md',
  poc_root: '.codemachine/artifacts/poc/',
  test_results: '.codemachine/artifacts/tests/results.json'
};

// Package-relative prompt locations used throughout the workflow.
export const packageDir = {
  protocol_architect_prompt: 'prompts/main/protocol-architect.md',
  poc_orchestrator_prompt: 'prompts/main/poc-orchestrator.md',
  qa_steward_prompt: 'prompts/main/qa-steward.md',
  final_packager_prompt: 'prompts/main/final-packager.md',
  coaching_scribe_prompt: 'prompts/sub/coaching-scribe.md',
  powershell_dev_prompt: 'prompts/sub/powershell-dev.md',
  docker_expert_prompt: 'prompts/sub/docker-expert.md',
  pester_tester_prompt: 'prompts/sub/pester-tester.md',
  quality_gate_prompt: 'prompts/modules/quality-gate.md'
};
