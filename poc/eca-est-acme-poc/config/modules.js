export default {
  modules: [
    {
      id: 'quality-gate',
      name: 'Quality Gate',
      description:
        'Evaluates QA steward results and loops development if outcomes fail to meet acceptance criteria.',
      promptPath: 'prompts/modules/quality-gate.md',
      behavior: {
        type: 'loop',
        action: 'stepBack',
        steps: 2,
        maxIterations: 3
      }
    }
  ]
};
