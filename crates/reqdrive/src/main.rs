//! `reqdrive story <work-order.json>`: runs one work order and writes JSON-lines events to
//! stdout, the last of which is the result.

use reqdrive::events::{Emitter, Event, Stage};
use reqdrive::outcome::{Category, Outcome, ResultEvent};
use reqdrive::{proc, story};
use std::any::Any;
use std::io;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

const USAGE: &str = "usage: reqdrive story <work-order.json>\n       reqdrive --version";

fn panic_message(p: &(dyn Any + Send)) -> String {
    p.downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| p.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "unknown panic".to_string())
}

/// Runs the story and writes its result. 0 once the result is written, 1 if it could not be.
fn story_command(work_order: &Path) -> i32 {
    let emitter = Emitter::new(Box::new(io::stdout()));
    if let Err(e) = proc::install_signal_handler() {
        eprintln!("[reqdrive] warning: cannot install the signal handler: {e}");
    }
    let env = story::Env::from_process();
    let result = catch_unwind(AssertUnwindSafe(|| story::run(work_order, &emitter, &env)))
        .unwrap_or_else(|p| {
            let detail = format!("the harness panicked: {}", panic_message(p.as_ref()));
            let _ = emitter.error(Category::HarnessError, detail.clone());
            // `story::run` emits `done` on every path it returns from; a panic skips it.
            let _ = emitter.emit(Event::Progress { stage: Stage::Done });
            ResultEvent::end(Outcome::Failed, Category::HarnessError, detail)
        });
    match emitter.finish(&result) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("[reqdrive] cannot write the result: {e}");
            1
        }
    }
}

fn main() {
    // Before any child is spawned, so none of them holds the orchestrator's pipes.
    if let Err(e) = proc::stop_std_handle_inheritance() {
        eprintln!("[reqdrive] warning: cannot make the std handles non-inheritable: {e}");
    }
    let args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    let code = match args.as_slice() {
        [flag] if flag == "--version" => {
            println!("reqdrive {}", env!("CARGO_PKG_VERSION"));
            0
        }
        [cmd, path] if cmd == "story" => story_command(Path::new(path)),
        _ => {
            eprintln!("{USAGE}");
            2
        }
    };
    std::process::exit(code);
}
