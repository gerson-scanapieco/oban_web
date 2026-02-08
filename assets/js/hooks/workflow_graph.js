import dagre from "dagre"
import panzoom from "panzoom"

const STATE_COLORS = {
  available: { fill: "#fef9c3", stroke: "#facc15", text: "#854d0e" },     // yellow
  cancelled: { fill: "#f3f4f6", stroke: "#9ca3af", text: "#374151" },     // gray
  completed: { fill: "#dcfce7", stroke: "#4ade80", text: "#166534" },     // green
  discarded: { fill: "#ffe4e6", stroke: "#fb7185", text: "#9f1239" },     // red/rose
  executing: { fill: "#dbeafe", stroke: "#60a5fa", text: "#1e40af" },     // blue
  retryable: { fill: "#ffedd5", stroke: "#fb923c", text: "#9a3412" },     // orange
  scheduled: { fill: "#f3f4f6", stroke: "#9ca3af", text: "#374151" },     // gray
}

const DARK_STATE_COLORS = {
  available: { fill: "#422006", stroke: "#facc15", text: "#fef9c3" },
  cancelled: { fill: "#1f2937", stroke: "#6b7280", text: "#d1d5db" },
  completed: { fill: "#052e16", stroke: "#4ade80", text: "#dcfce7" },
  discarded: { fill: "#4c0519", stroke: "#fb7185", text: "#ffe4e6" },
  executing: { fill: "#172554", stroke: "#60a5fa", text: "#dbeafe" },
  retryable: { fill: "#431407", stroke: "#fb923c", text: "#ffedd5" },
  scheduled: { fill: "#1f2937", stroke: "#6b7280", text: "#d1d5db" },
}

const NODE_WIDTH = 160
const NODE_HEIGHT = 48
const PADDING = 40

function isDarkMode() {
  return document.documentElement.classList.contains("dark")
}

function getColors(state) {
  const palette = isDarkMode() ? DARK_STATE_COLORS : STATE_COLORS
  return palette[state] || palette["cancelled"]
}

function layoutGraph(nodes) {
  const g = new dagre.graphlib.Graph()

  g.setGraph({
    rankdir: "LR",
    nodesep: 24,
    ranksep: 60,
    marginx: PADDING,
    marginy: PADDING,
  })

  g.setDefaultEdgeLabel(() => ({}))

  const nameMap = new Map()

  for (const node of nodes) {
    nameMap.set(node.name, node)
    g.setNode(node.name, { width: NODE_WIDTH, height: NODE_HEIGHT, ...node })
  }

  for (const node of nodes) {
    for (const dep of node.deps) {
      if (nameMap.has(dep)) {
        g.setEdge(dep, node.name)
      }
    }
  }

  dagre.layout(g)

  return g
}

function truncateText(text, maxLen) {
  if (text.length <= maxLen) return text
  return text.slice(0, maxLen - 1) + "…"
}

function renderGraph(container, g, jobPathPrefix) {
  while (container.firstChild) {
    container.removeChild(container.firstChild)
  }

  const graph = g.graph()
  const svgNS = "http://www.w3.org/2000/svg"

  const svg = document.createElementNS(svgNS, "svg")
  svg.setAttribute("width", "100%")
  svg.setAttribute("height", "100%")
  svg.style.display = "block"

  const defs = document.createElementNS(svgNS, "defs")

  const darkMode = isDarkMode()
  const markerColor = darkMode ? "#9ca3af" : "#6b7280"

  const marker = document.createElementNS(svgNS, "marker")
  marker.setAttribute("id", "arrowhead")
  marker.setAttribute("markerWidth", "8")
  marker.setAttribute("markerHeight", "6")
  marker.setAttribute("refX", "8")
  marker.setAttribute("refY", "3")
  marker.setAttribute("orient", "auto")

  const arrowPath = document.createElementNS(svgNS, "path")
  arrowPath.setAttribute("d", "M 0 0 L 8 3 L 0 6 Z")
  arrowPath.setAttribute("fill", markerColor)
  marker.appendChild(arrowPath)
  defs.appendChild(marker)
  svg.appendChild(defs)

  const graphGroup = document.createElementNS(svgNS, "g")
  graphGroup.classList.add("graph-container")

  // Render edges
  for (const e of g.edges()) {
    const edge = g.edge(e)
    const points = edge.points

    if (points.length < 2) continue

    const pathData = buildEdgePath(points)
    const edgePath = document.createElementNS(svgNS, "path")
    edgePath.setAttribute("d", pathData)
    edgePath.setAttribute("fill", "none")
    edgePath.setAttribute("stroke", markerColor)
    edgePath.setAttribute("stroke-width", "1.5")
    edgePath.setAttribute("marker-end", "url(#arrowhead)")
    graphGroup.appendChild(edgePath)
  }

  // Render nodes
  for (const nodeId of g.nodes()) {
    const node = g.node(nodeId)
    const colors = getColors(node.state)

    const group = document.createElementNS(svgNS, "g")
    group.setAttribute("transform", `translate(${node.x - NODE_WIDTH / 2}, ${node.y - NODE_HEIGHT / 2})`)
    group.style.cursor = "pointer"

    const rect = document.createElementNS(svgNS, "rect")
    rect.setAttribute("width", NODE_WIDTH)
    rect.setAttribute("height", NODE_HEIGHT)
    rect.setAttribute("rx", "8")
    rect.setAttribute("ry", "8")
    rect.setAttribute("fill", colors.fill)
    rect.setAttribute("stroke", colors.stroke)
    rect.setAttribute("stroke-width", "2")
    group.appendChild(rect)

    // Node name
    const nameText = document.createElementNS(svgNS, "text")
    nameText.setAttribute("x", NODE_WIDTH / 2)
    nameText.setAttribute("y", 20)
    nameText.setAttribute("text-anchor", "middle")
    nameText.setAttribute("fill", colors.text)
    nameText.setAttribute("font-size", "13")
    nameText.setAttribute("font-weight", "600")
    nameText.textContent = truncateText(node.name, 18)
    group.appendChild(nameText)

    // State label
    const stateText = document.createElementNS(svgNS, "text")
    stateText.setAttribute("x", NODE_WIDTH / 2)
    stateText.setAttribute("y", 37)
    stateText.setAttribute("text-anchor", "middle")
    stateText.setAttribute("fill", colors.text)
    stateText.setAttribute("font-size", "10")
    stateText.setAttribute("opacity", "0.75")
    stateText.textContent = node.state
    group.appendChild(stateText)

    group.addEventListener("click", (e) => {
      e.stopPropagation()
      const path = `${jobPathPrefix}/${node.id}`
      const link = document.createElement("a")
      link.setAttribute("href", path)
      link.setAttribute("data-phx-link", "patch")
      link.setAttribute("data-phx-link-state", "push")
      link.style.display = "none"
      document.body.appendChild(link)
      link.click()
      link.remove()
    })

    graphGroup.appendChild(group)
  }

  svg.appendChild(graphGroup)
  container.appendChild(svg)

  return { graphGroup, svg }
}

const ZOOM_FACTOR = 1.4

function createZoomControls(container, pzInstance) {
  const wrapper = document.createElement("div")
  wrapper.style.cssText = "position:absolute;bottom:8px;left:8px;display:flex;flex-direction:column;z-index:10;"

  const btnStyle = [
    "width:28px",
    "height:28px",
    "display:flex",
    "align-items:center",
    "justify-content:center",
    "cursor:pointer",
    "font-size:16px",
    "font-weight:600",
    "line-height:1",
    "border:1px solid",
    "user-select:none",
  ].join(";")

  const darkMode = isDarkMode()
  const colors = darkMode
    ? "background:#1f2937;color:#d1d5db;border-color:#374151;"
    : "background:#ffffff;color:#374151;border-color:#d1d5db;"

  const zoomIn = document.createElement("button")
  zoomIn.textContent = "+"
  zoomIn.setAttribute("type", "button")
  zoomIn.style.cssText = `${btnStyle};${colors}border-radius:4px 4px 0 0;border-bottom:none;`

  const zoomOut = document.createElement("button")
  zoomOut.textContent = "\u2212"
  zoomOut.setAttribute("type", "button")
  zoomOut.style.cssText = `${btnStyle};${colors}border-radius:0 0 4px 4px;`

  zoomIn.addEventListener("click", (e) => {
    e.stopPropagation()
    const rect = container.getBoundingClientRect()
    const cx = rect.width / 2
    const cy = rect.height / 2
    pzInstance.smoothZoom(cx, cy, ZOOM_FACTOR)
  })

  zoomOut.addEventListener("click", (e) => {
    e.stopPropagation()
    const rect = container.getBoundingClientRect()
    const cx = rect.width / 2
    const cy = rect.height / 2
    pzInstance.smoothZoom(cx, cy, 1 / ZOOM_FACTOR)
  })

  wrapper.appendChild(zoomIn)
  wrapper.appendChild(zoomOut)
  container.appendChild(wrapper)
}

function buildEdgePath(points) {
  if (points.length === 2) {
    return `M ${points[0].x} ${points[0].y} L ${points[1].x} ${points[1].y}`
  }

  let d = `M ${points[0].x} ${points[0].y}`

  for (let i = 1; i < points.length; i++) {
    d += ` L ${points[i].x} ${points[i].y}`
  }

  return d
}

const WorkflowGraph = {
  mounted() {
    this.panzoomInstance = null

    const data = this.el.dataset.graph
    if (data) {
      this.renderWorkflowGraph(JSON.parse(data))
    }
  },

  updated() {
    const data = this.el.dataset.graph
    if (data) {
      const savedTransform = this.saveTransform()
      this.renderWorkflowGraph(JSON.parse(data), savedTransform)
    }
  },

  saveTransform() {
    if (!this.panzoomInstance) return null
    return this.panzoomInstance.getTransform()
  },

  renderWorkflowGraph(nodes, savedTransform) {
    if (!nodes || nodes.length === 0) {
      this.el.style.display = "none"
      return
    }

    this.el.style.display = ""

    if (this.panzoomInstance) {
      this.panzoomInstance.dispose()
      this.panzoomInstance = null
    }

    const g = layoutGraph(nodes)
    const graph = g.graph()
    const jobPathPrefix = this.el.dataset.jobPathPrefix

    this.el.style.position = "relative"
    const { graphGroup } = renderGraph(this.el, g, jobPathPrefix)

    this.panzoomInstance = panzoom(graphGroup, {
      smoothScroll: false,
      bounds: true,
      boundsPadding: 0.2,
      maxZoom: 3,
      minZoom: 0.3,
    })

    if (savedTransform) {
      this.panzoomInstance.zoomAbs(0, 0, savedTransform.scale)
      this.panzoomInstance.moveTo(savedTransform.x, savedTransform.y)
    } else {
      const containerWidth = this.el.clientWidth
      const containerHeight = this.el.clientHeight
      const graphWidth = graph.width || 300
      const graphHeight = graph.height || 200

      const scaleX = containerWidth / graphWidth
      const scaleY = containerHeight / graphHeight
      const scale = Math.min(scaleX, scaleY, 1)

      const offsetX = (containerWidth - graphWidth * scale) / 2
      const offsetY = (containerHeight - graphHeight * scale) / 2

      this.panzoomInstance.zoomAbs(0, 0, scale)
      this.panzoomInstance.moveTo(offsetX, offsetY)
    }

    createZoomControls(this.el, this.panzoomInstance)
  },

  destroyed() {
    if (this.panzoomInstance) {
      this.panzoomInstance.dispose()
      this.panzoomInstance = null
    }
  },
}

export default WorkflowGraph
