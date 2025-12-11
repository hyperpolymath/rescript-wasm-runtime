// The Elm Architecture (TEA) in Pure ReScript - No React Dependencies
// SPDX-License-Identifier: AGPL-3.0-or-later

// Core TEA types
type cmd<'msg> =
  | NoCmd
  | Cmd(unit => option<'msg>)
  | Batch(array<cmd<'msg>>)

type sub<'msg> =
  | NoSub
  | Sub({
      id: string,
      subscribe: ('msg => unit) => unit => unit, // returns unsubscribe function
    })
  | BatchSub(array<sub<'msg>>)

// Program definition
type program<'model, 'msg> = {
  init: unit => ('model, cmd<'msg>),
  update: ('msg, 'model) => ('model, cmd<'msg>),
  view: 'model => Vdom.vnode,
  subscriptions: 'model => sub<'msg>,
}

// Command helpers
let none = NoCmd
let cmd = f => Cmd(f)
let batch = cmds => Batch(cmds)

// Subscription helpers
let noSub = NoSub
let sub = (id, subscribe) => Sub({id, subscribe})
let batchSub = subs => BatchSub(subs)

// Effect helpers for common patterns
module Effect = {
  // Delayed message
  let after = (ms: int, msg: 'msg): cmd<'msg> => {
    Cmd(() => {
      let _ = Js.Global.setTimeout(() => (), ms)
      Some(msg)
    })
  }

  // HTTP request (simplified)
  @val external fetch: string => Promise.t<'response> = "fetch"

  let http = (url: string, onSuccess: 'a => 'msg, onError: exn => 'msg): cmd<'msg> => {
    Cmd(() => {
      // This is a placeholder - actual implementation would use fetch
      None
    })
  }

  // Random number
  let random = (min: int, max: int, toMsg: int => 'msg): cmd<'msg> => {
    Cmd(() => {
      let value = Js.Math.random_int(min, max)
      Some(toMsg(value))
    })
  }

  // Focus an element
  let focus = (_id: string): cmd<'msg> => {
    Cmd(() => None)
  }
}

// Subscription helpers for common patterns
module Subscriptions = {
  // Timer subscription
  let every = (ms: int, msg: 'msg): sub<'msg> => {
    Sub({
      id: `timer_${ms->Int.toString}`,
      subscribe: dispatch => {
        let intervalId = Js.Global.setInterval(() => dispatch(msg), ms)
        () => Js.Global.clearInterval(intervalId)
      },
    })
  }

  // Window resize subscription
  @val external window: Dom.window = "window"
  @send external addWindowListener: (Dom.window, string, 'a => unit) => unit = "addEventListener"
  @send external removeWindowListener: (Dom.window, string, 'a => unit) => unit = "removeEventListener"

  let onResize = (toMsg: (int, int) => 'msg): sub<'msg> => {
    Sub({
      id: "window_resize",
      subscribe: dispatch => {
        let handler = _ => {
          // Get window dimensions and dispatch
          dispatch(toMsg(0, 0)) // Placeholder
        }
        window->addWindowListener("resize", handler)
        () => window->removeWindowListener("resize", handler)
      },
    })
  }

  // Keyboard subscription
  let onKeyDown = (toMsg: string => 'msg): sub<'msg> => {
    Sub({
      id: "keyboard_down",
      subscribe: dispatch => {
        let handler = _ => {
          dispatch(toMsg("")) // Placeholder - would extract key
        }
        window->addWindowListener("keydown", handler)
        () => window->removeWindowListener("keydown", handler)
      },
    })
  }
}

// Application state
type appState<'model, 'msg> = {
  mutable model: 'model,
  mutable root: option<Dom.element>,
  mutable currentVdom: option<Vdom.vnode>,
  mutable subscriptions: array<unit => unit>, // Unsubscribe functions
}

// Process commands
let rec processCmd = (state: appState<'model, 'msg>, dispatch: 'msg => unit, cmd: cmd<'msg>) => {
  switch cmd {
  | NoCmd => ()
  | Cmd(f) =>
    switch f() {
    | Some(msg) => dispatch(msg)
    | None => ()
    }
  | Batch(cmds) => cmds->Array.forEach(c => processCmd(state, dispatch, c))
  }
}

// Process subscriptions
let rec processSub = (
  dispatch: 'msg => unit,
  sub: sub<'msg>,
): array<unit => unit> => {
  switch sub {
  | NoSub => []
  | Sub({subscribe, _}) => [subscribe(dispatch)]
  | BatchSub(subs) =>
    subs->Array.flatMap(s => processSub(dispatch, s))
  }
}

// Main render loop
let render = (state: appState<'model, 'msg>, program: program<'model, 'msg>) => {
  switch state.root {
  | Some(root) => {
      let newVdom = program.view(state.model)
      Vdom.mount(root, newVdom)
      state.currentVdom = Some(newVdom)
    }
  | None => ()
  }
}

// Create and run a TEA application
let run = (
  program: program<'model, 'msg>,
  rootId: string,
): unit => {
  // Initialize state
  let (initialModel, initialCmd) = program.init()

  let state: appState<'model, 'msg> = {
    model: initialModel,
    root: None,
    currentVdom: None,
    subscriptions: [],
  }

  // Dispatch function
  let rec dispatch = (msg: 'msg) => {
    let (newModel, cmd) = program.update(msg, state.model)
    state.model = newModel

    // Re-render
    render(state, program)

    // Process command
    processCmd(state, dispatch, cmd)

    // Update subscriptions
    state.subscriptions->Array.forEach(unsub => unsub())
    state.subscriptions = processSub(dispatch, program.subscriptions(state.model))
  }

  // Get root element
  switch Vdom.document->Vdom.getElementById(rootId)->Nullable.toOption {
  | Some(root) => {
      state.root = Some(root)

      // Initial render
      render(state, program)

      // Process initial command
      processCmd(state, dispatch, initialCmd)

      // Set up initial subscriptions
      state.subscriptions = processSub(dispatch, program.subscriptions(state.model))
    }
  | None => Js.Console.error(`Element with id "${rootId}" not found`)
  }
}

// Simple program without subscriptions
let simple = (
  ~init: unit => 'model,
  ~update: ('msg, 'model) => 'model,
  ~view: 'model => Vdom.vnode,
): program<'model, 'msg> => {
  init: () => (init(), NoCmd),
  update: (msg, model) => (update(msg, model), NoCmd),
  view,
  subscriptions: _ => NoSub,
}
