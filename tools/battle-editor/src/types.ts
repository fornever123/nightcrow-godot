export type JsonObject = Record<string, any>;

export interface AssetFile {
  path: string;
  size: number;
  modifiedAt: string;
  extension: string;
  kind: 'image' | 'audio' | 'video' | 'file';
  previewable: boolean;
  url: string;
}

export interface ValidationResult {
  ok: boolean;
  errors: string[];
  warnings: string[];
  summary?: JsonObject;
}

export interface ConfigPayload {
  config: JsonObject;
  validation: ValidationResult;
}

export interface EditorProject {
  schemaVersion: number;
  workspace: {
    activeSection?: string;
    selectedCharacter?: number;
    selectedMove?: number;
    selectedAssetPath?: string;
    zoom?: number;
    panX?: number;
    panY?: number;
  };
  documents: JsonObject;
}
