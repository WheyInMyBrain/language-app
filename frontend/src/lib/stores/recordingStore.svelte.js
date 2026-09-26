// frontend/src/lib/stores/recordingStore.svelte.js
class RecordingStore {
  isRecording = $state(false);

  start() {
    this.isRecording = true;
  }

  stop() {
    this.isRecording = false;
  }
}

export const recordingStore = new RecordingStore();