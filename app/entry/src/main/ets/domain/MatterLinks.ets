import { AppState, ChecklistItem, Matter, ModuleInstance, ModuleType } from '../model/Types';

export function canLinkMatterInState(state: AppState, ownerMatterId: string, targetMatterId: string): boolean {
  const owner = state.matters.find((matter: Matter) => matter.id === ownerMatterId);
  const target = state.matters.find((matter: Matter) => matter.id === targetMatterId);
  if (!owner || !target || owner.id === target.id || owner.archived || target.archived ||
    !owner.enabledModules.some((module: ModuleInstance) => module.moduleType === ModuleType.Checklist)) {
    return false;
  }
  // 已被引用的事项不能继续引用事项；同一目标也不能重复被引用。
  if (state.checklistItems.some((item: ChecklistItem) => item.entryType === 'matter_ref' &&
    (item.targetMatterId === ownerMatterId || item.targetMatterId === targetMatterId))) {
    return false;
  }
  return !state.checklistItems.some((item: ChecklistItem) => {
    return item.matterId === targetMatterId && item.entryType === 'matter_ref';
  });
}
