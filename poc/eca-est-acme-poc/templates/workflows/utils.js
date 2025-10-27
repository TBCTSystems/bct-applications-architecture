import mainAgents from '../../config/main.agents.js';
import modules from '../../config/modules.js';

const agentMap = new Map(mainAgents.agents.map((agent) => [agent.id, agent]));
const moduleMap = new Map(modules.modules.map((module) => [module.id, module]));

export const resolveStep = (agentId, overrides = {}) => {
  const agent = agentMap.get(agentId);

  if (!agent) {
    throw new Error(`Unknown agent: ${agentId}`);
  }

  const {
    agentName,
    promptPath,
    notCompletedFallback,
    ...executionOverrides
  } = overrides;

  const step = {
    type: 'agent',
    id: agent.id,
    name: agentName ?? agent.name,
    description: agent.description,
    promptPath: promptPath ?? agent.promptPath,
    ...executionOverrides
  };

  if (notCompletedFallback) {
    step.notCompletedFallback = notCompletedFallback;
  }

  return step;
};

export const resolveModule = (moduleId, overrides = {}) => {
  const module = moduleMap.get(moduleId);

  if (!module) {
    throw new Error(`Unknown module: ${moduleId}`);
  }

  const {
    promptPath,
    loopSteps,
    loopMaxIterations,
    loopSkip,
    ...executionOverrides
  } = overrides;

  const behavior = module.behavior ? { ...module.behavior } : undefined;

  if (behavior) {
    if (typeof loopSteps === 'number') {
      behavior.steps = loopSteps;
    }

    if (typeof loopMaxIterations === 'number') {
      behavior.maxIterations = loopMaxIterations;
    }

    if (Array.isArray(loopSkip)) {
      behavior.skip = loopSkip;
    }
  }

  return {
    type: 'module',
    id: module.id,
    name: module.name,
    promptPath: promptPath ?? module.promptPath,
    behavior,
    ...executionOverrides
  };
};
