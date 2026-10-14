import { ref } from 'vue'

// The one trailer the app is playing; App.vue shows it in a TrailerModal.
export const playing = ref(null)
export const playTrailer = (key, name = '', kind = '') => { playing.value = { key, name, kind } }
