import type {AssetFile, ConfigPayload, EditorProject, JsonObject, ValidationResult} from '../types';

async function request<T>(url: string, options?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...options,
    headers: {'Content-Type': 'application/json', ...(options?.headers || {})}
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error || `请求失败：${response.status}`) as Error & {payload?: JsonObject};
    error.payload = payload;
    throw error;
  }
  return payload as T;
}

export const api = {
  loadConfig: () => request<{ok: true} & ConfigPayload>('/api/config'),
  loadAssets: () => request<{ok: true; assets: AssetFile[]}>('/api/assets'),
  loadEditorProject: () => request<{ok: true; project: EditorProject}>('/api/editor-project'),
  saveConfig: (config: JsonObject) => request<{ok: true; backup: string | null; validation: ValidationResult}>('/api/config', {method: 'POST', body: JSON.stringify(config)}),
  saveEditorProject: (project: EditorProject) => request<{ok: true; backup: string | null}>('/api/editor-project', {method: 'POST', body: JSON.stringify(project)}),
  saveProject: (config: JsonObject, project: EditorProject) => request<{ok: true; backup: string | null; validation: ValidationResult}>('/api/project/save', {method: 'POST', body: JSON.stringify({config, project})}),
  backups: () => request<{ok: true; backups: {name: string; modifiedAt: string}[]}>('/api/backups'),
  loadBackup: (name: string) => request<{ok: true; value: JsonObject}>('/api/backup?name=' + encodeURIComponent(name)),
  trash: () => request<{ok: true; entries: {id: string; path: string; deletedAt: string}[]}>('/api/trash'),
  restoreAsset: (id: string) => request<{ok: true; path: string}>('/api/asset/restore', {method: 'POST', body: JSON.stringify({id})}),
  validate: (config: JsonObject) => request<{ok: true; validation: ValidationResult}>('/api/validate', {method: 'POST', body: JSON.stringify(config)}),
  upload: (payload: JsonObject) => request<{ok: true; path: string; size: number}>('/api/upload', {method: 'POST', body: JSON.stringify(payload)}),
  renameAsset: (path: string, name: string) => request<{ok: true; path: string}>('/api/asset/rename', {method: 'POST', body: JSON.stringify({path, name})}),
  deleteAsset: (path: string) => request<{ok: true; trashPath: string}>('/api/asset/delete', {method: 'POST', body: JSON.stringify({path})}),
  gameStatus: () => request<{ok: true; status: JsonObject}>('/api/game/status'),
  startGame: () => request<{ok: true; status: JsonObject; message: string}>('/api/game/start', {method: 'POST'}),
  stopGame: () => request<{ok: true; status: JsonObject; message: string}>('/api/game/stop', {method: 'POST'})
};
