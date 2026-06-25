// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/wikihub"
import topbar from "../vendor/topbar"
import * as THREE from "../vendor/three/three.module.js"
import {OrbitControls} from "../vendor/three/OrbitControls.js"
import {CSS2DRenderer, CSS2DObject} from "../vendor/three/CSS2DRenderer.js"

const Hooks = {}

// Draws a note's title onto a canvas so it can sit on a 3D placard in the room.
function noteTexture(title, color) {
  const cw = 256, ch = 192
  const cv = document.createElement("canvas")
  cv.width = cw; cv.height = ch
  const ctx = cv.getContext("2d")
  ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, cw, ch)
  ctx.fillStyle = color; ctx.fillRect(0, 0, cw, 10)
  ctx.fillStyle = "#1a1a1c"
  ctx.font = "600 21px Inter, system-ui, sans-serif"
  ctx.textBaseline = "top"
  const words = String(title).split(/\s+/)
  const lines = []
  let line = ""
  const maxW = cw - 28
  words.forEach(w => {
    const t = line ? line + " " + w : w
    if (ctx.measureText(t).width > maxW && line) { lines.push(line); line = w } else line = t
  })
  if (line) lines.push(line)
  lines.slice(0, 7).forEach((ln, i) => ctx.fillText(ln, 14, 26 + i * 24))
  const tex = new THREE.CanvasTexture(cv)
  tex.anisotropy = 4
  return tex
}

// 3D mind palace (three.js). Folders are walled rooms on a floor plan, notes are
// placards inside them, refs are floor corridors. Orbit to look around, click a
// note to read it. Falls back to the 2D plan if WebGL is unavailable.
Hooks.Palace = {
  mounted() { try { this.init() } catch (e) { console.error("palace:", e) } },
  destroyed() { this.teardown() },
  init() {
    const rooms = JSON.parse(this.el.dataset.rooms || "[]")
    const links = JSON.parse(this.el.dataset.links || "[]")
    if (!rooms.length) return
    const el = this.el
    let W = el.clientWidth, H = el.clientHeight || 480

    const renderer = new THREE.WebGLRenderer({antialias: true})
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(W, H)
    el.appendChild(renderer.domElement)

    const labelRenderer = new CSS2DRenderer()
    labelRenderer.setSize(W, H)
    labelRenderer.domElement.className = "label-layer"
    el.appendChild(labelRenderer.domElement)

    const scene = new THREE.Scene()
    scene.background = new THREE.Color(0xfbfaf6)
    const camera = new THREE.PerspectiveCamera(48, W / H, 0.5, 5000)
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.dampingFactor = 0.08
    controls.maxPolarAngle = Math.PI * 0.49
    controls.minDistance = 24

    scene.add(new THREE.HemisphereLight(0xffffff, 0xcfcabb, 1.05))
    const dir = new THREE.DirectionalLight(0xffffff, 0.35)
    dir.position.set(120, 260, 160)
    scene.add(dir)

    // --- layout: pack rooms into a grid; notes into a sub-grid per room ---
    const TILE_W = 16, TILE_D = 12, GAP = 6, PAD = 8, NOTE_H = 12, WALL_H = 7, ROOM_GAP = 26
    const dims = rooms.map(r => {
      const cols = Math.ceil(Math.sqrt(Math.max(1, r.notes.length)))
      const rws = Math.ceil(Math.max(1, r.notes.length) / cols)
      return {cols, w: cols * TILE_W + (cols - 1) * GAP + PAD * 2, d: rws * TILE_D + (rws - 1) * GAP + PAD * 2}
    })
    const roomCols = Math.ceil(Math.sqrt(rooms.length))
    const placed = []
    let i = 0, z = 0, totalW = 0
    while (i < rooms.length) {
      const row = []
      let rowD = 0
      for (let c = 0; c < roomCols && i < rooms.length; c++, i++) { row.push(i); rowD = Math.max(rowD, dims[i].d) }
      let x = 0
      row.forEach(idx => { placed[idx] = {x: x + dims[idx].w / 2, z: z + rowD / 2, w: dims[idx].w, d: rowD}; x += dims[idx].w + ROOM_GAP })
      totalW = Math.max(totalW, x - ROOM_GAP)
      z += rowD + ROOM_GAP
    }
    const totalD = z - ROOM_GAP
    const offX = -totalW / 2, offZ = -totalD / 2

    const pickables = [], noteMeshes = new Map(), notePos = new Map()
    const edgeMat = new THREE.LineBasicMaterial({color: 0x2a2a2e, transparent: true, opacity: 0.45})

    rooms.forEach((room, idx) => {
      const p = placed[idx]
      const rx = offX + p.x, rz = offZ + p.z
      const col = new THREE.Color(room.color)
      const floor = new THREE.Mesh(
        new THREE.BoxGeometry(p.w, 1, p.d),
        new THREE.MeshStandardMaterial({color: col.clone().lerp(new THREE.Color(0xffffff), 0.62), roughness: 1})
      )
      floor.position.set(rx, -0.5, rz)
      scene.add(floor)
      const walls = new THREE.LineSegments(
        new THREE.EdgesGeometry(new THREE.BoxGeometry(p.w, WALL_H, p.d)),
        new THREE.LineBasicMaterial({color: col.clone().lerp(new THREE.Color(0x000000), 0.15)})
      )
      walls.position.set(rx, WALL_H / 2, rz)
      scene.add(walls)

      const div = document.createElement("div")
      div.className = "pl-room-label"
      div.innerHTML = `${room.name} <b>${room.notes.length}</b>`
      const lbl = new CSS2DObject(div)
      lbl.position.set(rx, WALL_H + 6, rz - p.d / 2)
      scene.add(lbl)

      room.notes.forEach((note, ni) => {
        const c = ni % dims[idx].cols, rr = Math.floor(ni / dims[idx].cols)
        const nx = rx - p.w / 2 + PAD + c * (TILE_W + GAP) + TILE_W / 2
        const nz = rz - p.d / 2 + PAD + rr * (TILE_D + GAP) + TILE_D / 2
        const face = new THREE.MeshStandardMaterial({map: noteTexture(note.title, room.color), roughness: 0.95})
        const side = new THREE.MeshStandardMaterial({color: col, roughness: 0.95})
        const mesh = new THREE.Mesh(new THREE.BoxGeometry(TILE_W, NOTE_H, 0.8), [side, side, side, side, face, face])
        mesh.position.set(nx, NOTE_H / 2, nz)
        mesh.userData = note
        mesh.add(new THREE.LineSegments(new THREE.EdgesGeometry(mesh.geometry), edgeMat))
        scene.add(mesh)
        pickables.push(mesh)
        noteMeshes.set(note.id, mesh)
        notePos.set(note.id, mesh.position.clone())
      })
    })

    const corridors = new THREE.Group()
    corridors.visible = false
    scene.add(corridors)
    const lines = []
    links.forEach(([from, to]) => {
      const a = notePos.get(from), b = notePos.get(to)
      if (!a || !b) return
      const geo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(a.x, 1.5, a.z), new THREE.Vector3(b.x, 1.5, b.z)])
      const ln = new THREE.Line(geo, new THREE.LineBasicMaterial({color: 0x1f6feb, transparent: true, opacity: 0.35}))
      ln.userData = {from, to}
      corridors.add(ln)
      lines.push(ln)
    })

    const span = Math.max(totalW, totalD, 60)
    camera.position.set(span * 0.7, span * 0.8, span * 0.95)
    controls.maxDistance = span * 3
    controls.target.set(0, 0, 0)
    controls.update()
    const home = camera.position.clone()

    const ray = new THREE.Raycaster(), mouse = new THREE.Vector2()
    let hovered = null
    const setMouse = (e) => {
      const r = renderer.domElement.getBoundingClientRect()
      mouse.x = ((e.clientX - r.left) / r.width) * 2 - 1
      mouse.y = -((e.clientY - r.top) / r.height) * 2 + 1
    }
    const pick = () => { ray.setFromCamera(mouse, camera); const h = ray.intersectObjects(pickables, false)[0]; return h && h.object }
    const highlight = (id) => {
      noteMeshes.forEach((m, mid) => m.scale.setScalar(id && mid === id ? 1.18 : 1))
      if (corridors.visible) lines.forEach(ln => {
        const hot = id && (ln.userData.from === id || ln.userData.to === id)
        ln.material.opacity = id ? (hot ? 0.95 : 0.05) : 0.35
        ln.material.color.set(hot ? 0x0b4fc4 : 0x1f6feb)
      })
    }
    const onMove = (e) => {
      setMouse(e)
      const obj = pick()
      el.style.cursor = obj ? "pointer" : "grab"
      if (obj !== hovered) { hovered = obj; highlight(hovered && hovered.userData.id) }
    }
    const onClick = (e) => { setMouse(e); const obj = pick(); if (obj) window.location.href = obj.userData.url }
    renderer.domElement.addEventListener("pointermove", onMove)
    renderer.domElement.addEventListener("click", onClick)

    const root = el.closest(".hub-main") || document
    const handlers = []
    const on = (t, ev, fn) => { if (t) { t.addEventListener(ev, fn); handlers.push([t, ev, fn]) } }
    on(root.querySelector("[data-bp-links]"), "change", (e) => { corridors.visible = e.target.checked; highlight(hovered && hovered.userData.id) })
    on(root.querySelector("[data-bp-reset]"), "click", () => { camera.position.copy(home); controls.target.set(0, 0, 0); controls.update() })
    on(root.querySelector("[data-bp-search]"), "input", (e) => {
      const q = e.target.value.trim().toLowerCase()
      let found = null
      noteMeshes.forEach((m, id) => {
        const hit = q && (m.userData.title.toLowerCase().includes(q) || id.toLowerCase().includes(q))
        m.scale.setScalar(hit ? 1.3 : 1)
        if (hit && !found) found = m
      })
      if (found) { controls.target.copy(found.position); controls.update() }
    })

    const ro = new ResizeObserver(() => {
      W = el.clientWidth; H = el.clientHeight || 480
      camera.aspect = W / H; camera.updateProjectionMatrix()
      renderer.setSize(W, H); labelRenderer.setSize(W, H)
    })
    ro.observe(el)

    let raf
    const tick = () => { controls.update(); renderer.render(scene, camera); labelRenderer.render(scene, camera); raf = requestAnimationFrame(tick) }
    tick()

    el.classList.add("is-3d")
    this._t = {renderer, labelRenderer, controls, scene, ro, handlers, stop: () => cancelAnimationFrame(raf)}
  },
  teardown() {
    const t = this._t
    if (!t) return
    t.stop()
    t.ro.disconnect()
    t.handlers.forEach(([el, ev, fn]) => el.removeEventListener(ev, fn))
    t.scene.traverse(o => {
      if (o.geometry) o.geometry.dispose()
      if (o.material) [].concat(o.material).forEach(m => { if (m.map) m.map.dispose(); m.dispose() })
    })
    t.controls.dispose()
    t.renderer.dispose()
    t.renderer.domElement.remove()
    t.labelRenderer.domElement.remove()
    this.el.classList.remove("is-3d")
  }
}

// Global search: '/' or Cmd/Ctrl+K to focus, Escape to clear, Up/Down + Enter to navigate results.
Hooks.GlobalSearch = {
  mounted() {
    this.onKey = (e) => {
      const tag = (document.activeElement && document.activeElement.tagName) || ""
      const typing = tag === "INPUT" || tag === "TEXTAREA"
      if (e.key === "/" && !typing) { e.preventDefault(); this.el.focus(); this.el.select() }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); this.el.focus(); this.el.select() }
    }
    document.addEventListener("keydown", this.onKey)

    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { this.el.value = ""; this.pushEvent("global_search", { q: "" }); this.el.blur(); return }
      const overlay = document.getElementById("search-overlay")
      if (!overlay) return
      const hits = Array.from(overlay.querySelectorAll(".search-hit"))
      if (!hits.length) return
      let i = hits.findIndex(h => h.classList.contains("is-sel"))
      if (e.key === "ArrowDown") { e.preventDefault(); this.select(hits, Math.min(i + 1, hits.length - 1)) }
      else if (e.key === "ArrowUp") { e.preventDefault(); this.select(hits, Math.max(i - 1, 0)) }
      else if (e.key === "Enter") { e.preventDefault(); (overlay.querySelector(".search-hit.is-sel") || hits[0]).click() }
    })
  },
  select(hits, i) {
    hits.forEach(h => h.classList.remove("is-sel"))
    if (hits[i]) { hits[i].classList.add("is-sel"); hits[i].scrollIntoView({ block: "nearest" }) }
  },
  destroyed() { document.removeEventListener("keydown", this.onKey) }
}

// Copy-to-clipboard button (onboarding command).
Hooks.Copy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const target = this.el.dataset.copyTarget
      const node = target && document.querySelector(target)
      const text = node ? node.textContent : ""
      if (navigator.clipboard) navigator.clipboard.writeText(text)
      const old = this.el.textContent
      this.el.textContent = "copied ✓"
      setTimeout(() => { this.el.textContent = old }, 1200)
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

