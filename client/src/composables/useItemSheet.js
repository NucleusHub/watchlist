import { ref } from 'vue'

// Titles open as a sheet over the page they were opened from: `?item=<id>` on any route.
// Bumped whenever the sheet changes or deletes a title, so the page behind can reload.
export const itemsVersion = ref(0)
export const itemsChanged = () => itemsVersion.value++

export function closeItemSheet(router) {
  const route = router.currentRoute.value
  const { item, ...query } = route.query
  const back = window.history.state?.back
  const prev = back ? router.resolve(back) : null
  // Opened from this same page: going back closes it and keeps history tidy; a direct link just drops the query.
  if (prev && prev.path === route.path && !prev.query.item) router.back()
  else router.replace({ path: route.path, query })
}
