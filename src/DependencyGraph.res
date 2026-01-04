// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Hyperpolymath

@@ocaml.doc("
Directed Acyclic Graph (DAG) builder for dependency analysis.
Handles circular dependency detection to ensure ecosystem 'root' repos
are never flagged for elimination.

Key invariant: If A depends on B and B depends on A, identify the 'root'
(most depended-upon) and only flag satellites for elimination.
")

// ============================================================================
// Types
// ============================================================================

@ocaml.doc("Node in the dependency graph")
type node = {
  id: string,
  name: string,
  mutable inDegree: int,   // Number of nodes pointing TO this node
  mutable outDegree: int,  // Number of nodes this points TO
  mutable visited: bool,
  mutable inStack: bool,   // For cycle detection
  mutable depth: int,      // Topological depth
}

@ocaml.doc("Edge in the dependency graph")
type edge = {
  from: string,
  to: string,
  weight: option<float>,  // Optional edge weight for scoring
}

@ocaml.doc("Cycle detected in the graph")
type cycle = {
  nodes: array<string>,
  suggestedRoot: string,  // The node that should be kept
}

@ocaml.doc("Dependency graph")
type t = {
  mutable nodes: Js.Dict.t<node>,
  mutable edges: array<edge>,
  mutable adjacency: Js.Dict.t<array<string>>,      // outgoing edges
  mutable reverseAdj: Js.Dict.t<array<string>>,     // incoming edges
}

@ocaml.doc("Analysis result")
type analysisResult = {
  isDAG: bool,
  cycles: array<cycle>,
  roots: array<string>,           // Nodes with inDegree 0
  leaves: array<string>,          // Nodes with outDegree 0
  topologicalOrder: option<array<string>>,
  eliminationCandidates: array<string>,
  criticalPath: array<string>,
}

// ============================================================================
// Graph Construction
// ============================================================================

@ocaml.doc("Create an empty dependency graph")
let create = (): t => {
  {
    nodes: Js.Dict.empty(),
    edges: [],
    adjacency: Js.Dict.empty(),
    reverseAdj: Js.Dict.empty(),
  }
}

@ocaml.doc("Add a node to the graph")
let addNode = (graph: t, id: string, ~name: string=?, ()): unit => {
  let nodeName = name->Option.getOr(id)
  if Js.Dict.get(graph.nodes, id)->Option.isNone {
    Js.Dict.set(graph.nodes, id, {
      id,
      name: nodeName,
      inDegree: 0,
      outDegree: 0,
      visited: false,
      inStack: false,
      depth: -1,
    })
    Js.Dict.set(graph.adjacency, id, [])
    Js.Dict.set(graph.reverseAdj, id, [])
  }
}

@ocaml.doc("Add an edge (dependency) to the graph")
let addEdge = (graph: t, ~from: string, ~to: string, ~weight: option<float>=?, ()): unit => {
  // Ensure both nodes exist
  addNode(graph, from, ())
  addNode(graph, to, ())

  // Add edge
  graph.edges = Array.concat(graph.edges, [{from, to, weight}])

  // Update adjacency lists
  let outgoing = Js.Dict.get(graph.adjacency, from)->Option.getOr([])
  if !Array.includes(outgoing, to) {
    Js.Dict.set(graph.adjacency, from, Array.concat(outgoing, [to]))

    let incoming = Js.Dict.get(graph.reverseAdj, to)->Option.getOr([])
    Js.Dict.set(graph.reverseAdj, to, Array.concat(incoming, [from]))

    // Update degrees
    switch Js.Dict.get(graph.nodes, from) {
    | Some(node) => node.outDegree = node.outDegree + 1
    | None => ()
    }
    switch Js.Dict.get(graph.nodes, to) {
    | Some(node) => node.inDegree = node.inDegree + 1
    | None => ()
    }
  }
}

@ocaml.doc("Add dependency: 'dependent' depends on 'dependency'")
let addDependency = (graph: t, ~dependent: string, ~dependency: string): unit => {
  addEdge(graph, ~from=dependent, ~to=dependency, ())
}

// ============================================================================
// Cycle Detection
// ============================================================================

@ocaml.doc("Reset visited flags for traversal")
let resetVisited = (graph: t): unit => {
  Js.Dict.values(graph.nodes)->Array.forEach(node => {
    node.visited = false
    node.inStack = false
  })
}

@ocaml.doc("Find all cycles using DFS")
let findCycles = (graph: t): array<cycle> => {
  resetVisited(graph)
  let cycles: ref<array<cycle>> = ref([])
  let stack: ref<array<string>> = ref([])

  let rec dfs = (nodeId: string): unit => {
    switch Js.Dict.get(graph.nodes, nodeId) {
    | None => ()
    | Some(node) => {
        node.visited = true
        node.inStack = true
        stack := Array.concat(stack.contents, [nodeId])

        let neighbors = Js.Dict.get(graph.adjacency, nodeId)->Option.getOr([])
        neighbors->Array.forEach(neighborId => {
          switch Js.Dict.get(graph.nodes, neighborId) {
          | None => ()
          | Some(neighbor) => {
              if neighbor.inStack {
                // Found cycle! Extract it from stack
                let cycleStart = stack.contents->Array.findIndex(id => id == neighborId)
                if cycleStart >= 0 {
                  let cycleNodes = stack.contents->Array.sliceToEnd(~start=cycleStart)

                  // Determine suggested root (highest inDegree in cycle)
                  let suggestedRoot = cycleNodes->Array.reduce(neighborId, (best, id) => {
                    let bestNode = Js.Dict.get(graph.nodes, best)
                    let currentNode = Js.Dict.get(graph.nodes, id)
                    switch (bestNode, currentNode) {
                    | (Some(b), Some(c)) if c.inDegree > b.inDegree => id
                    | _ => best
                    }
                  })

                  cycles := Array.concat(cycles.contents, [{
                    nodes: cycleNodes,
                    suggestedRoot,
                  }])
                }
              } else if !neighbor.visited {
                dfs(neighborId)
              }
            }
          }
        })

        node.inStack = false
        stack := stack.contents->Array.slice(~start=0, ~end=Array.length(stack.contents) - 1)
      }
    }
  }

  // Run DFS from each unvisited node
  Js.Dict.keys(graph.nodes)->Array.forEach(nodeId => {
    switch Js.Dict.get(graph.nodes, nodeId) {
    | Some(node) if !node.visited => dfs(nodeId)
    | _ => ()
    }
  })

  cycles.contents
}

// ============================================================================
// Topological Sort
// ============================================================================

@ocaml.doc("Kahn's algorithm for topological sort")
let topologicalSort = (graph: t): option<array<string>> => {
  let inDegree = Js.Dict.empty()
  let queue: ref<array<string>> = ref([])
  let result: ref<array<string>> = ref([])

  // Initialize in-degrees
  Js.Dict.entries(graph.nodes)->Array.forEach(((id, node)) => {
    Js.Dict.set(inDegree, id, node.inDegree)
    if node.inDegree == 0 {
      queue := Array.concat(queue.contents, [id])
    }
  })

  // Process queue
  while Array.length(queue.contents) > 0 {
    let current = queue.contents->Array.getUnsafe(0)
    queue := queue.contents->Array.sliceToEnd(~start=1)
    result := Array.concat(result.contents, [current])

    let neighbors = Js.Dict.get(graph.adjacency, current)->Option.getOr([])
    neighbors->Array.forEach(neighbor => {
      let deg = Js.Dict.get(inDegree, neighbor)->Option.getOr(0)
      let newDeg = deg - 1
      Js.Dict.set(inDegree, neighbor, newDeg)
      if newDeg == 0 {
        queue := Array.concat(queue.contents, [neighbor])
      }
    })
  }

  // Check if all nodes are processed (no cycles)
  if Array.length(result.contents) == Array.length(Js.Dict.keys(graph.nodes)) {
    Some(result.contents)
  } else {
    None
  }
}

// ============================================================================
// Root and Leaf Detection
// ============================================================================

@ocaml.doc("Find root nodes (no incoming edges - these are the ecosystem roots)")
let findRoots = (graph: t): array<string> => {
  Js.Dict.entries(graph.nodes)
  ->Array.filter(((_, node)) => node.inDegree == 0)
  ->Array.map(((id, _)) => id)
}

@ocaml.doc("Find leaf nodes (no outgoing edges)")
let findLeaves = (graph: t): array<string> => {
  Js.Dict.entries(graph.nodes)
  ->Array.filter(((_, node)) => node.outDegree == 0)
  ->Array.map(((id, _)) => id)
}

// ============================================================================
// Elimination Scoring
// ============================================================================

@ocaml.doc("Calculate elimination score for a node (higher = more redundant)")
let eliminationScore = (graph: t, nodeId: string): float => {
  switch Js.Dict.get(graph.nodes, nodeId) {
  | None => 0.0
  | Some(node) => {
      // Factors that increase elimination score:
      // - Low inDegree (few things depend on it)
      // - High outDegree (it depends on many things)
      // - Not in a critical path

      let inScore = if node.inDegree == 0 {
        0.5  // Might be a root, less likely to eliminate
      } else {
        1.0 /. Float.fromInt(node.inDegree + 1)
      }

      let outScore = Float.fromInt(node.outDegree) /. 10.0

      // Base score
      inScore +. outScore
    }
  }
}

@ocaml.doc("Find elimination candidates (redundant satellites)")
let findEliminationCandidates = (graph: t, ~threshold: float=0.5, ()): array<string> => {
  let roots = findRoots(graph)

  Js.Dict.keys(graph.nodes)
  ->Array.filter(id => {
    // Never eliminate roots
    if roots->Array.includes(id) {
      false
    } else {
      eliminationScore(graph, id) >= threshold
    }
  })
}

// ============================================================================
// Critical Path
// ============================================================================

@ocaml.doc("Find the critical path (longest path through graph)")
let findCriticalPath = (graph: t): array<string> => {
  switch topologicalSort(graph) {
  | None => []  // Has cycles, can't find critical path
  | Some(order) => {
      // Calculate depths
      let depths = Js.Dict.empty()
      let parents = Js.Dict.empty()

      order->Array.forEach(id => {
        Js.Dict.set(depths, id, 0)
        Js.Dict.set(parents, id, None)
      })

      // Forward pass - calculate max depth to each node
      order->Array.forEach(id => {
        let currentDepth = Js.Dict.get(depths, id)->Option.getOr(0)
        let neighbors = Js.Dict.get(graph.adjacency, id)->Option.getOr([])

        neighbors->Array.forEach(neighbor => {
          let neighborDepth = Js.Dict.get(depths, neighbor)->Option.getOr(0)
          if currentDepth + 1 > neighborDepth {
            Js.Dict.set(depths, neighbor, currentDepth + 1)
            Js.Dict.set(parents, neighbor, Some(id))
          }
        })
      })

      // Find node with max depth
      let maxNode = order->Array.reduce(order->Array.getUnsafe(0), (best, id) => {
        let bestDepth = Js.Dict.get(depths, best)->Option.getOr(0)
        let idDepth = Js.Dict.get(depths, id)->Option.getOr(0)
        if idDepth > bestDepth { id } else { best }
      })

      // Backtrack to build path
      let path: ref<array<string>> = ref([maxNode])
      let current = ref(maxNode)

      while Js.Dict.get(parents, current.contents)->Option.flatMap(x => x)->Option.isSome {
        let parent = Js.Dict.get(parents, current.contents)->Option.flatMap(x => x)->Option.getExn
        path := Array.concat([parent], path.contents)
        current := parent
      }

      path.contents
    }
  }
}

// ============================================================================
// Full Analysis
// ============================================================================

@ocaml.doc("Run complete dependency analysis")
let analyze = (graph: t): analysisResult => {
  let cycles = findCycles(graph)
  let topoOrder = topologicalSort(graph)
  let roots = findRoots(graph)
  let leaves = findLeaves(graph)
  let candidates = findEliminationCandidates(graph, ())
  let criticalPath = findCriticalPath(graph)

  {
    isDAG: Array.length(cycles) == 0,
    cycles,
    roots,
    leaves,
    topologicalOrder: topoOrder,
    eliminationCandidates: candidates,
    criticalPath,
  }
}

// ============================================================================
// Serialization for SharedMemory
// ============================================================================

@ocaml.doc("Serialize graph to compact format for WASM")
let toCompactFormat = (graph: t): {
  "nodeCount": int,
  "edgeCount": int,
  "nodeIds": array<string>,
  "edges": array<(int, int)>,
} => {
  let nodeIds = Js.Dict.keys(graph.nodes)
  let nodeIndex = Js.Dict.empty()
  nodeIds->Array.forEachWithIndex((id, i) => {
    Js.Dict.set(nodeIndex, id, i)
  })

  let edges = graph.edges->Array.filterMap(edge => {
    let fromIdx = Js.Dict.get(nodeIndex, edge.from)
    let toIdx = Js.Dict.get(nodeIndex, edge.to)
    switch (fromIdx, toIdx) {
    | (Some(f), Some(t)) => Some((f, t))
    | _ => None
    }
  })

  {
    "nodeCount": Array.length(nodeIds),
    "edgeCount": Array.length(edges),
    "nodeIds": nodeIds,
    "edges": edges,
  }
}

// ============================================================================
// Pretty Printing
// ============================================================================

@ocaml.doc("Format analysis result as string")
let formatAnalysis = (result: analysisResult): string => {
  let lines: ref<array<string>> = ref([])

  lines := Array.concat(lines.contents, [
    `DAG Status: ${result.isDAG ? "Valid DAG" : "Contains Cycles"}`,
    `Roots (ecosystem anchors): ${result.roots->Array.join(", ")}`,
    `Leaves: ${result.leaves->Array.join(", ")}`,
  ])

  if Array.length(result.cycles) > 0 {
    lines := Array.concat(lines.contents, ["\nCycles Detected:"])
    result.cycles->Array.forEach(cycle => {
      lines := Array.concat(lines.contents, [
        `  ${cycle.nodes->Array.join(" -> ")} -> ${cycle.nodes->Array.getUnsafe(0)}`,
        `  Suggested root to keep: ${cycle.suggestedRoot}`,
      ])
    })
  }

  if Array.length(result.eliminationCandidates) > 0 {
    lines := Array.concat(lines.contents, [
      `\nElimination Candidates: ${result.eliminationCandidates->Array.join(", ")}`,
    ])
  }

  if Array.length(result.criticalPath) > 0 {
    lines := Array.concat(lines.contents, [
      `Critical Path: ${result.criticalPath->Array.join(" -> ")}`,
    ])
  }

  lines.contents->Array.join("\n")
}
