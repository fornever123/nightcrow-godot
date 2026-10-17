import type {EditorProject, JsonObject} from '../types';

export function defaultEditorProject(): EditorProject {
  return {
    schemaVersion: 1,
    workspace: {activeSection: 'overview', selectedCharacter: 0, selectedMove: 0, selectedAssetPath: '', zoom: 1, panX: 0, panY: 0},
    documents: {}
  };
}

export function mergeEditorProject(value: Partial<EditorProject> | null | undefined): EditorProject {
  const fallback = defaultEditorProject();
  return {
    schemaVersion: typeof value?.schemaVersion === 'number' ? value.schemaVersion : fallback.schemaVersion,
    workspace: {...fallback.workspace, ...(value?.workspace || {})},
    documents: {...fallback.documents, ...(value?.documents || {})}
  };
}

export function clone<T extends JsonObject>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}
