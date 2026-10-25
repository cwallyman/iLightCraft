//! Cancellable native photo merges run off the bridge thread; only finishing mutates the catalog.

use crate::status::Failure;
use lightcraft_engine::{
    Session,
    catalog::PhotoId,
    merge::{MergeJob, MergeOutput},
};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex, PoisonError,
    atomic::{AtomicBool, Ordering},
};

#[derive(Default)]
pub struct MergeJobs {
    current: Option<Running>,
}
struct Running {
    job: Arc<MergeJob>,
    cancel: Arc<AtomicBool>,
    state: Arc<Mutex<State>>,
    result: Option<Value>,
}
struct State {
    fraction: f32,
    stage: String,
    done: bool,
    output: Option<Result<MergeOutput, String>>,
}
impl Drop for MergeJobs {
    fn drop(&mut self) {
        if let Some(run) = &self.current {
            run.cancel.store(true, Ordering::Release);
        }
    }
}
impl MergeJobs {
    pub fn abandon(&mut self) {
        self.cancel();
        self.current = None;
    }
    pub fn cancel(&self) {
        if let Some(run) = &self.current {
            run.cancel.store(true, Ordering::Release);
        }
    }
    pub fn execute(
        &mut self,
        session: &mut Session,
        command: &str,
        params: &Value,
    ) -> Result<Value, Failure> {
        if command == "ilightcraft.mergeCancel" {
            if let Some(run) = &self.current {
                run.cancel.store(true, Ordering::Release);
            }
            return Ok(json!({"cancelling": true}));
        }
        if command == "ilightcraft.mergeStatus" {
            return self.poll(session);
        }
        if self
            .current
            .as_ref()
            .is_some_and(|r| !r.state.lock().unwrap_or_else(PoisonError::into_inner).done)
        {
            return Err(Failure::invalid("A photo merge is already running"));
        }
        let ids: Vec<u64> = serde_json::from_value(params.get("ids").cloned().unwrap_or(Value::Null))
            .map_err(|_| Failure::invalid("Choose the photos to merge"))?;
        if !(2..=12).contains(&ids.len()) {
            return Err(Failure::invalid("Select between 2 and 12 photos"));
        }
        let unique: std::collections::HashSet<u64> = ids.iter().copied().collect();
        if unique.len() != ids.len() {
            return Err(Failure::invalid("A source photo was selected more than once"));
        }
        let mut pixels = 0u64;
        for id in &ids {
            let photo = session
                .catalog
                .photo(PhotoId(*id))
                .ok_or_else(|| Failure::invalid("A selected source no longer exists"))?;
            let count = u64::from(photo.width)
                .checked_mul(u64::from(photo.height))
                .ok_or_else(|| Failure::invalid("Source dimensions overflow"))?;
            if count == 0 || count > 80_000_000 {
                return Err(Failure::invalid(
                    "Merge sources must be between 1 and 80 megapixels",
                ));
            }
            pixels = pixels
                .checked_add(count)
                .ok_or_else(|| Failure::invalid("Source dimensions overflow"))?;
        }
        let kind = params.get("kind").and_then(Value::as_str).unwrap_or("hdr");
        let engine_command = match kind {
            "hdr" => "merge.hdr",
            "panorama" => "merge.panorama",
            "hdrPanorama" => "merge.hdrPanorama",
            _ => return Err(Failure::invalid("Unknown merge mode")),
        };
        let mut options = params.clone();
        let max_mp = params
            .get("maxMegapixels")
            .and_then(Value::as_f64)
            .unwrap_or(20.0);
        if !max_mp.is_finite() || !(1.0..=40.0).contains(&max_mp) {
            return Err(Failure::invalid(
                "Merge output limit must be between 1 and 40 megapixels",
            ));
        }
        options["maxMegapixels"] = json!(max_mp);
        let available = params
            .get("availableBytes")
            .and_then(Value::as_u64)
            .unwrap_or(0)
            .min(6 * 1024 * 1024 * 1024);
        let estimate = pixels
            .checked_mul(64)
            .and_then(|n| n.checked_add((max_mp * 1_000_000.0) as u64 * 48))
            .ok_or_else(|| Failure::invalid("Merge memory estimate overflow"))?;
        if available == 0 || estimate > available.saturating_mul(3) / 5 {
            return Err(Failure::invalid(
                "These full-resolution sources exceed the current merge memory allowance. Use smaller source files, fewer frames, or a Mac with more free memory.",
            ));
        }
        let (kind, finish) =
            lightcraft_engine::merge::parse(engine_command, &options).map_err(Failure::engine)?;
        let ids: Vec<PhotoId> = ids.into_iter().map(PhotoId).collect();
        let job = Arc::new(
            session
                .plan_merge(kind, finish, &ids, false)
                .map_err(Failure::engine)?,
        );
        let cancel = Arc::new(AtomicBool::new(false));
        let state = Arc::new(Mutex::new(State {
            fraction: 0.0,
            stage: "Preparing merge".into(),
            done: false,
            output: None,
        }));
        let worker_job = Arc::clone(&job);
        let worker_cancel = Arc::clone(&cancel);
        let worker_state = Arc::clone(&state);
        std::thread::Builder::new()
            .name("native-photo-merge".into())
            .stack_size(8 * 1024 * 1024)
            .spawn(move || {
                let output = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    worker_job.run(&|fraction, stage| {
                        if worker_cancel.load(Ordering::Acquire) {
                            return false;
                        }
                        let mut state = worker_state.lock().unwrap_or_else(PoisonError::into_inner);
                        state.fraction = if fraction.is_finite() {
                            fraction.clamp(0.0, 1.0)
                        } else {
                            0.0
                        };
                        state.stage = stage.chars().take(200).collect();
                        true
                    })
                }))
                .unwrap_or_else(|_| {
                    Err("The merge worker stopped unexpectedly; source photos are unchanged.".into())
                });
                let mut state = worker_state.lock().unwrap_or_else(PoisonError::into_inner);
                state.done = true;
                state.output = Some(output);
            })
            .map_err(|e| Failure::invalid(format!("Cannot start the merge worker: {e}")))?;
        self.current = Some(Running {
            job,
            cancel,
            state,
            result: None,
        });
        Ok(json!({"state": "running"}))
    }
    fn poll(&mut self, session: &mut Session) -> Result<Value, Failure> {
        let Some(run) = &mut self.current else {
            return Ok(json!({"state": "idle"}));
        };
        if let Some(result) = &run.result {
            return Ok(result.clone());
        }
        let output = {
            let mut state = run.state.lock().unwrap_or_else(PoisonError::into_inner);
            if !state.done {
                return Ok(json!({"state": "running", "progress": state.fraction, "stage": state.stage}));
            }
            state.output.take()
        };
        let result = if run.cancel.load(Ordering::Acquire) {
            json!({"state": "cancelled"})
        } else {
            match output {
                Some(Ok(out)) => match session.finish_merge(&run.job, out) {
                    Ok(result) => json!({"state": "completed", "result": result}),
                    Err(error) => json!({"state": "failed", "error": error.to_string()}),
                },
                Some(Err(error)) => json!({"state": "failed", "error": error}),
                None => json!({"state": "failed", "error": "No merge output was produced"}),
            }
        };
        run.result = Some(result.clone());
        Ok(result)
    }
}
