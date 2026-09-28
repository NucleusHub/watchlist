import icon from '@/assets/splash-icon.png'
import mark from '@/assets/nucleus-mark.png'

// The native launch screen (ios/App/App/Base.lproj/LaunchScreen.storyboard)
// can't move. This draws the same layout in the web view, so swapping one
// for the other is invisible, and then lets it go in about a third of a
// second — the icon lifts and fades while the page shows through. Quick on
// purpose: it hands over, it isn't something to watch.

const CSS = `
.lh-root {
  position: fixed; inset: 0; z-index: 10000; pointer-events: none;
  font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  color: #fff; -webkit-font-smoothing: antialiased;
}
.lh-bg { position: absolute; inset: 0; background: #0d0d1a; }
.lh-icon {
  position: absolute; left: 50%; top: 50%; width: 120px; height: 120px;
  margin: -60px 0 0 -60px;
}
.lh-title {
  position: absolute; left: 0; right: 0; top: calc(50% + 79.67px);
  text-align: center; font-size: 28px; line-height: 34px; font-weight: 700;
}
.lh-foot {
  position: absolute; left: 0; right: 0;
  bottom: calc(env(safe-area-inset-bottom, 0px) + 12px);
  display: flex; flex-direction: column; align-items: center; gap: 4px;
}
.lh-from { font-size: 13px; line-height: 16px; color: rgba(255, 255, 255, 0.45); }
.lh-row { display: flex; align-items: center; gap: 6px; height: 22px; font-size: 17px; font-weight: 600; color: rgba(255, 255, 255, 0.9); }
.lh-row img { width: 22px; height: 22px; }

.lh-go .lh-bg { opacity: 0; transition: opacity 0.3s cubic-bezier(0.4, 0, 0.2, 1) 0.04s; }
.lh-go .lh-icon { opacity: 0; transform: scale(1.14); transition: transform 0.34s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.26s ease-in 0.06s; }
.lh-go .lh-title { opacity: 0; transform: translateY(6px); transition: opacity 0.14s ease-in, transform 0.2s ease-in; }
.lh-go .lh-foot { opacity: 0; transition: opacity 0.14s ease-in; }
@media (prefers-reduced-motion: reduce) {
  .lh-go .lh-icon, .lh-go .lh-title { transform: none; }
}
`

let root = null

/** Put the copy up before the app mounts, so it's there when the native one goes. */
export function showLaunchCopy() {
  const style = document.createElement('style')
  style.textContent = CSS
  root = document.createElement('div')
  root.className = 'lh-root'
  root.setAttribute('aria-hidden', 'true')
  root.innerHTML = `
    <div class="lh-bg"></div>
    <img class="lh-icon" src="${icon}" alt="">
    <div class="lh-title">Watchlist</div>
    <div class="lh-foot">
      <span class="lh-from">from</span>
      <span class="lh-row"><img src="${mark}" alt="">Nucleus</span>
    </div>`
  root.prepend(style)
  document.body.appendChild(root)
}

/** Once the first page has painted: drop the native screen and animate the copy away. */
export async function handOver() {
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
  try {
    const { SplashScreen } = await import('@capacitor/splash-screen')
    await SplashScreen.hide({ fadeOutDuration: 0 })
  } catch {}
  if (!root) return
  const el = root
  root = null
  requestAnimationFrame(() => {
    el.classList.add('lh-go')
    setTimeout(() => el.remove(), 420)
  })
}
