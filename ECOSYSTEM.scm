;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
;; ECOSYSTEM.scm — rescript-wasm-runtime

(ecosystem
  (version "1.0.0")
  (name "rescript-wasm-runtime")
  (type "project")
  (purpose "High-performance, type-safe HTTP server runtime combining ReScript with WASM compilation targets")

  (position-in-ecosystem
    "Part of hyperpolymath ecosystem. Follows RSR guidelines.")

  (related-projects
    (project (name "rhodium-standard-repositories")
             (url "https://github.com/hyperpolymath/rhodium-standard-repositories")
             (relationship "standard")))

  (what-this-is "A minimal footprint HTTP server framework for Deno/Bun with ReScript type safety")
  (what-this-is-not "- NOT exempt from RSR compliance"))
