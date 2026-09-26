// frontend/src/lib/stores/uploadProgress.svelte.js

class UploadProgressStore {
  // Overall aggregated progress: 0 to 100
  progress = $state(0);
  isUploading = $state(false);
  
  // Total pending items remaining in IndexedDB outbox
  pendingCount = $state(0);

  #activeTasks = new Map(); // id -> { loaded, total }

  setPendingCount(count) {
    this.pendingCount = Math.max(0, Number(count) || 0);
  }

  startTask(id, totalBytes = 0) {
    this.#activeTasks.set(id, { loaded: 0, total: totalBytes || 1 });
    this.isUploading = true;
    this.#recompute();
  }

  updateTask(id, loaded, total) {
    if (!this.#activeTasks.has(id)) return;
    this.#activeTasks.set(id, { loaded, total });
    this.#recompute();
  }

  finishTask(id) {
    this.#activeTasks.delete(id);
    if (this.#activeTasks.size === 0) {
      this.progress = 100;
      // Brief delay so the user catches the completed bar before it resets
      setTimeout(() => {
        if (this.#activeTasks.size === 0) {
          this.isUploading = false;
          this.progress = 0;
        }
      }, 400);
    } else {
      this.#recompute();
    }
  }

  #recompute() {
    let totalLoaded = 0;
    let totalSize = 0;

    for (const { loaded, total } of this.#activeTasks.values()) {
      totalLoaded += loaded;
      totalSize += total;
    }

    if (totalSize > 0) {
      this.progress = Math.min(100, Math.round((totalLoaded / totalSize) * 100));
    }
  }
}

export const uploadProgressStore = new UploadProgressStore();