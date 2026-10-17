export class History<T extends object> {
  private entries: string[] = [];
  private cursor = -1;

  get canUndo() { return this.cursor > 0; }
  get canRedo() { return this.cursor < this.entries.length - 1; }

  constructor(initial: T) {
    this.reset(initial);
  }

  reset(value: T) {
    const snapshot = JSON.stringify(value);
    this.entries = [snapshot];
    this.cursor = 0;
  }

  push(value: T) {
    const snapshot = JSON.stringify(value);
    if (this.entries[this.cursor] === snapshot) return;
    this.entries = this.entries.slice(0, this.cursor + 1);
    this.entries.push(snapshot);
    if (this.entries.length > 100) this.entries.shift();
    this.cursor = this.entries.length - 1;
  }

  undo(): T | null {
    if (this.cursor <= 0) return null;
    this.cursor -= 1;
    return JSON.parse(this.entries[this.cursor]) as T;
  }

  redo(): T | null {
    if (this.cursor >= this.entries.length - 1) return null;
    this.cursor += 1;
    return JSON.parse(this.entries[this.cursor]) as T;
  }
}
