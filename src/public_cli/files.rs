use super::*;

pub(super) fn stat_entries(paths: &[String]) -> AppResult<Vec<Value>> {
    let normalized: Vec<String> = paths.iter().map(|path| absolute_path(path)).collect();
    let mut command = vec!["stat-batch".to_string()];
    for path in &normalized {
        command.extend(["--path".to_string(), path.clone()]);
    }
    let response = backend_json(&command)?;
    let entries = response
        .get("entries")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let unique: HashSet<&str> = normalized.iter().map(String::as_str).collect();
    if !response.get("ok").and_then(Value::as_bool).unwrap_or(false)
        || entries.len() != unique.len()
    {
        return Err(AppError::command(error_text(
            &response,
            "Could not inspect every selected path",
        )));
    }
    Ok(entries)
}

pub(super) fn select_paths(paths: &[String]) -> AppResult<()> {
    let entries = stat_entries(paths)?;
    let encoded = encoded_document(&Value::Array(entries))?;
    let response = ipc("selectEntries", &[encoded])?;
    if response == "ok" {
        Ok(())
    } else {
        Err(AppError::command(response))
    }
}

pub(super) fn selection_paths() -> AppResult<Vec<String>> {
    let document = object_response("selection", &[])?;
    Ok(document
        .get("paths")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|path| !path.is_empty())
        .map(ToOwned::to_owned)
        .collect())
}

pub(super) fn history_navigation(method: &str, options: WaitTenArgs) -> AppResult<PublicResult> {
    let before = options
        .wait
        .then(|| object_response("status", &[]))
        .transpose()?;
    let response = ipc(method, &[])?;
    if !options.wait || response != "checking" {
        return Ok(PublicResult::one(response));
    }
    let before = before.unwrap_or_default();
    let stack = if method == "back" {
        "rootBackStack"
    } else {
        "rootForwardStack"
    };
    let allowed: HashSet<String> = before
        .get(stack)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(location_resource)
        .collect();
    let previous = location_resource(before.get("rootPath").and_then(Value::as_str).unwrap_or(""));
    let result = poll(
        options.timeout,
        || {
            let state = object_response("status", &[])?;
            for key in ["activeLocationMode", "pendingLocationMode"] {
                let mode = state.get(key).and_then(Value::as_str).unwrap_or("");
                if !mode.is_empty() && mode != method {
                    return Err(AppError::command(
                        "Folder-history navigation was replaced before it completed",
                    ));
                }
            }
            if state
                .get("locationValidationBusy")
                .and_then(Value::as_bool)
                .unwrap_or(false)
                || nonempty(&state, "activeLocationPath")
                || nonempty(&state, "pendingLocationPath")
            {
                return Ok(None);
            }
            if nonempty(&state, "locationValidationError") {
                return Err(AppError::command(text_field(
                    &state,
                    "locationValidationError",
                )));
            }
            let root = location_resource(&text_field(&state, "rootPath"));
            if root == previous {
                return Ok(None);
            }
            if !allowed.contains(&root) {
                return Err(AppError::command(
                    "Folder-history navigation was replaced before it completed",
                ));
            }
            Ok(Some(Value::Object(state)))
        },
        &format!("Timed out waiting for {method} navigation"),
    )?;
    Ok(PublicResult::many(vec![Value::String(response), result]))
}

pub(super) fn hidden(options: HiddenArgs) -> AppResult<PublicResult> {
    match options.state {
        HiddenState::Toggle => simple_ipc("toggleHidden", &[]),
        HiddenState::Show => simple_ipc("setShowHidden", &["true".to_string()]),
        HiddenState::Hide => simple_ipc("setShowHidden", &["false".to_string()]),
    }
}

pub(super) fn select(paths: Vec<String>) -> AppResult<PublicResult> {
    select_paths(&paths)?;
    json_ipc("selection", &[])
}

pub(super) fn menu(options: MenuArgs) -> AppResult<PublicResult> {
    if !options.paths.is_empty() {
        select_paths(&options.paths)?;
    }
    simple_ipc(
        if options.open_with {
            "showOpenWith"
        } else {
            "showActions"
        },
        &[],
    )
}

pub(super) fn settle_clipboard() -> AppResult<()> {
    poll(
        3.0,
        || {
            let Ok(state) = object_response("status", &[]) else {
                return Ok(Some(Value::Null));
            };
            let busy = state
                .get("clipboardBusy")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            Ok((!busy).then_some(Value::Null))
        },
        "Timed out waiting for the clipboard to update",
    )
    .map(|_| ())
}

pub(super) fn selection_clipboard(paths: Vec<String>, cut: bool) -> AppResult<PublicResult> {
    let response = if paths.is_empty() {
        ipc("copySelection", &[cut.to_string()])?
    } else {
        select_paths(&paths)?;
        let absolute: Vec<String> = paths.iter().map(|path| absolute_path(path)).collect();
        ipc(
            "copyFilesOf",
            &[encoded_document(&json!(absolute))?, cut.to_string()],
        )?
    };
    if response == "no-selection" {
        return Err(AppError::command(response));
    }
    settle_clipboard()?;
    Ok(PublicResult::one(response))
}

pub(super) fn selection_paths_clipboard(paths: Vec<String>) -> AppResult<PublicResult> {
    let response = if paths.is_empty() {
        ipc("copyPaths", &[])?
    } else {
        select_paths(&paths)?;
        let absolute: Vec<String> = paths.iter().map(|path| absolute_path(path)).collect();
        ipc("copyPathsOf", &[encoded_document(&json!(absolute))?])?
    };
    if response == "no-selection" {
        return Err(AppError::command(response));
    }
    settle_clipboard()?;
    Ok(PublicResult::one(response))
}

pub(super) fn paste(options: PasteArgs) -> AppResult<PublicResult> {
    let destination = options
        .destination
        .map(|path| absolute_path(&path))
        .unwrap_or_default();
    let conflict = crate::backend::value_name(options.on_conflict);
    operation_response(ipc("pasteWith", &[destination, conflict])?, options.wait)
}

pub(super) fn transfer(options: TransferArgs, copy: bool) -> AppResult<PublicResult> {
    if !options.paths.is_empty() {
        select_paths(&options.paths)?;
    }
    let destination = absolute_path(&options.destination);
    let response = ipc(
        "transferSelection",
        &[
            destination.clone(),
            copy.to_string(),
            crate::backend::value_name(options.on_conflict),
        ],
    )?;
    operation_response(response, options.wait)
}

pub(super) fn rename(options: RenameArgs) -> AppResult<PublicResult> {
    if let Some(path) = options.path {
        select_paths(&[path])?;
    }
    operation_response(
        ipc("renameSelection", std::slice::from_ref(&options.name))?,
        options.wait,
    )
}

pub(super) fn create(options: CreateArgs, directory: bool) -> AppResult<PublicResult> {
    let parent = options
        .parent
        .map(|path| absolute_path(&path))
        .unwrap_or_default();
    let response = ipc(
        "createEntry",
        &[options.name, directory.to_string(), parent],
    )?;
    operation_response(response, options.wait)
}

pub(super) fn trash(options: TrashArgs) -> AppResult<PublicResult> {
    if !options.paths.is_empty() {
        select_paths(&options.paths)?;
    }
    operation_response(ipc("trashSelection", &[])?, options.wait)
}

pub(super) fn trash_list(options: TrashListArgs) -> AppResult<PublicResult> {
    let result = backend_json(&[
        "trash-list".to_string(),
        "--limit".to_string(),
        options.limit.to_string(),
    ])?;
    Ok(PublicResult::checked(result, "Could not list Trash"))
}

pub(super) fn trash_restore(options: TrashRestoreArgs) -> AppResult<PublicResult> {
    let mut arguments = vec!["trash-restore".to_string(), "--id".to_string(), options.id];
    if !options.destination.is_empty() {
        arguments.extend(["--destination".to_string(), options.destination]);
    }
    if options.recreate_parent {
        arguments.push("--recreate-parent".to_string());
    }
    let result = backend_json_with_timeout(&arguments, MUTATION_BACKEND_TIMEOUT)?;
    Ok(PublicResult::checked(
        result,
        "Could not restore the Trash entry",
    ))
}

pub(super) fn trash_delete(options: TrashDeleteArgs) -> AppResult<PublicResult> {
    if !options.yes {
        return Err(AppError::invalid("permanent Trash deletion requires --yes"));
    }
    let mut arguments = vec!["trash-delete".to_string()];
    for id in options.id {
        arguments.extend(["--id".to_string(), id]);
    }
    let result = backend_json_with_timeout(&arguments, MUTATION_BACKEND_TIMEOUT)?;
    Ok(PublicResult::checked(
        result,
        "Could not permanently delete every Trash entry",
    ))
}

pub(super) fn trash_empty(options: TrashEmptyArgs) -> AppResult<PublicResult> {
    if !options.yes {
        return Err(AppError::invalid("emptying Trash requires --yes"));
    }
    let result = backend_json_with_timeout(&["trash-empty".to_string()], MUTATION_BACKEND_TIMEOUT)?;
    Ok(PublicResult::checked(result, "Could not empty Trash"))
}

pub(super) fn history_step(direction: &str, options: HistoryStepArgs) -> AppResult<PublicResult> {
    let response = ipc(
        direction,
        &[options.drop.to_string(), options.force.to_string()],
    )?;
    let explained = match response.as_str() {
        "nothing-to-undo" => Some("Nothing to undo"),
        "nothing-to-redo" => Some("Nothing to redo"),
        "busy" => Some("Wait for the current undo or redo to finish"),
        "not-refused" => Some(
            "--drop only skips an entry that was refused; the next entry was not refused, so run it without --drop",
        ),
        _ => None,
    };
    if let Some(message) = explained {
        return Err(AppError::command(message));
    }
    operation_response(response, options.wait)
}

pub(super) fn history(options: HistoryArgs) -> AppResult<PublicResult> {
    if options.refresh {
        let _ = ipc("refreshHistory", &[])?;
    }
    json_ipc("history", &[])
}

pub(super) fn operation_response(
    response: String,
    wait: WaitThirtyArgs,
) -> AppResult<PublicResult> {
    if !response.starts_with("op-") {
        return Err(AppError::command(if response.is_empty() {
            "File operation was not queued".to_string()
        } else {
            response
        }));
    }
    if !wait.wait {
        return Ok(PublicResult::one(response));
    }
    let result = wait_for_operation(&response, wait.timeout)?;
    Ok(PublicResult::many(vec![Value::String(response), result]))
}

pub(super) fn wait_for_operation(request_id: &str, timeout: f64) -> AppResult<Value> {
    let mut pending = false;
    let waited = poll(
        timeout,
        || {
            let outcome = settled_operation(&operation_result(request_id)?, request_id);
            pending = matches!(outcome, Ok(None));
            outcome
        },
        &format!("Timed out waiting for file operation {request_id}"),
    );
    match waited {
        Err(_) if pending => abandon_operation(request_id, timeout),
        waited => waited,
    }
}

fn operation_result(request_id: &str) -> AppResult<Value> {
    Ok(Value::Object(object_response(
        "operationResult",
        &[request_id.to_string()],
    )?))
}

fn settled_operation(result: &Value, request_id: &str) -> AppResult<Option<Value>> {
    match result.get("status").and_then(Value::as_str).unwrap_or("") {
        "succeeded" => Ok(Some(result.clone())),
        "failed" => Err(AppError::command(error_text(
            result,
            "File operation failed",
        ))),
        "cancelled" => Err(AppError::command(error_text(
            result,
            "File operation was cancelled",
        ))),
        "unknown" => Err(AppError::command(format!(
            "Unknown file operation: {request_id}"
        ))),
        _ => Ok(None),
    }
}

fn abandon_operation(request_id: &str, timeout: f64) -> AppResult<Value> {
    let timed_out = format!("Timed out waiting for file operation {request_id} after {timeout}s");
    let still_pending = |reason: &str| {
        AppError::command(format!(
            "{timed_out}; {reason}; check it with `omablade operation {request_id}`"
        ))
    };
    let response = ipc("cancelOperation", &[request_id.to_string()])
        .map_err(|error| still_pending(&format!("it may still run ({error})")))?;
    if response == "not-cancellable" {
        return Err(still_pending("it is still running and cannot be cancelled"));
    }
    if !matches!(response.as_str(), "cancelled" | "cancelling" | "complete") {
        return Err(still_pending(&format!("it may still run ({response})")));
    }
    let deadline = Instant::now() + OPERATION_CANCEL_GRACE;
    loop {
        let result = operation_result(request_id)?;
        match result.get("status").and_then(Value::as_str).unwrap_or("") {
            "cancelled" => {
                return Err(AppError::command(format!(
                    "{timed_out}; cancelled it, so it will not run later"
                )));
            }
            "succeeded" | "failed" | "unknown" => {
                return settled_operation(&result, request_id)?
                    .ok_or_else(|| still_pending("it may still run"));
            }
            _ if Instant::now() >= deadline => {
                return Err(still_pending(
                    "cancellation was requested but has not finished",
                ));
            }
            _ => thread::sleep(Duration::from_millis(100)),
        }
    }
}

pub(super) fn cancel_operation(options: CancelOperationArgs) -> AppResult<PublicResult> {
    let request_id = match options.request_id {
        Some(value) if !value.is_empty() => value,
        _ => text_field(&object_response("status", &[])?, "activeOperationId"),
    };
    if request_id.is_empty() {
        return Err(AppError::command("No active operation"));
    }
    let response = ipc("cancelOperation", &[request_id])?;
    if matches!(
        response.as_str(),
        "unknown" | "not-cancellable" | "complete"
    ) {
        return Err(AppError::command(response));
    }
    Ok(PublicResult::one(response))
}

pub(super) fn git_refresh(options: WaitTenArgs) -> AppResult<PublicResult> {
    let previous = if options.wait {
        integer_field(
            &object_response("status", &[])?,
            "gitMetadataIpcRefreshCount",
        )
    } else {
        0
    };
    let response = ipc("refreshGit", &[])?;
    if !options.wait
        || matches!(
            response.as_str(),
            "inactive" | "no-repositories" | "no-visible-paths"
        )
    {
        return Ok(PublicResult::one(response));
    }
    let state = poll(
        options.timeout,
        || {
            let state = object_response("status", &[])?;
            if nonempty(&state, "gitMetadataError")
                && !state
                    .get("gitMetadataBusy")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
            {
                return Err(AppError::command(text_field(&state, "gitMetadataError")));
            }
            let complete = integer_field(&state, "gitMetadataIpcRefreshCount") > previous;
            Ok(complete.then_some(Value::Object(state)))
        },
        "Timed out waiting for Git metadata refresh",
    )?;
    let summary = json!({
        "status": "complete",
        "refreshCount": value_i64(&state, "gitMetadataRefreshCount"),
        "noopCount": value_i64(&state, "gitMetadataNoopCount"),
        "paths": value_i64(&state, "lastGitMetadataPathCount"),
        "repositories": value_i64(&state, "lastGitMetadataRepositoryCount"),
        "reason": value_text(&state, "lastGitMetadataReason"),
        "error": value_text(&state, "gitMetadataError"),
    });
    Ok(PublicResult::many(vec![Value::String(response), summary]))
}

pub(super) fn color(color: String, paths: Vec<String>) -> AppResult<PublicResult> {
    if !paths.is_empty() {
        select_paths(&paths)?;
    }
    let response = ipc("colorSelection", &[color])?;
    let selection = response_value(&ipc("selection", &[])?);
    Ok(PublicResult::many(vec![Value::String(response), selection]))
}

pub(super) fn favorites_batch(paths: Vec<String>, pin: bool) -> AppResult<PublicResult> {
    let method = if pin { "pinMany" } else { "unpinMany" };
    let value = if pin {
        Value::Array(stat_entries(&paths)?)
    } else {
        let mut seen = HashSet::new();
        Value::Array(
            paths
                .iter()
                .map(|path| absolute_path(path))
                .filter(|path| seen.insert(path.clone()))
                .map(Value::String)
                .collect(),
        )
    };
    let result = Value::Object(object_response(method, &[encoded_document(&value)?])?);
    if !result.get("ok").and_then(Value::as_bool).unwrap_or(false) {
        return Err(AppError::command(error_text(
            &result,
            &format!("Favorite batch method {method} failed"),
        )));
    }
    Ok(PublicResult::one(result))
}

pub(super) fn navigation(method: &str, options: NavigateArgs) -> AppResult<PublicResult> {
    let target = location_resource(&options.path);
    let response = ipc(method, std::slice::from_ref(&target))?;
    if !options.wait.wait {
        return Ok(PublicResult::one(response));
    }
    let result = poll(
        options.wait.timeout,
        || {
            let state = object_response("status", &[])?;
            let requested = text_field(&state, "locationValidationPath");
            if !requested.is_empty() && requested != target {
                return Err(AppError::command(
                    "Location navigation was replaced before it completed",
                ));
            }
            if state
                .get("locationValidationBusy")
                .and_then(Value::as_bool)
                .unwrap_or(false)
                || nonempty(&state, "activeLocationPath")
                || nonempty(&state, "pendingLocationPath")
            {
                return Ok(None);
            }
            if nonempty(&state, "locationValidationError") {
                return Err(AppError::command(text_field(
                    &state,
                    "locationValidationError",
                )));
            }
            Ok((text_field(&state, "rootPath") == target).then_some(Value::Object(state)))
        },
        "Timed out waiting for location navigation",
    )?;
    Ok(PublicResult::many(vec![Value::String(response), result]))
}

pub(super) fn expansion(method: &str, path: String) -> AppResult<PublicResult> {
    let path = absolute_path(&path);
    let response = ipc(method, std::slice::from_ref(&path))?;
    match response.as_str() {
        "not-visible" => Err(AppError::command(format!(
            "{path} is not shown in the tree; open the folder that contains it first"
        ))),
        "not-directory" => Err(AppError::command(format!("{path} is not a folder"))),
        _ => Ok(PublicResult::one(response)),
    }
}

pub(super) fn root(options: RootArgs) -> AppResult<PublicResult> {
    match options.path {
        Some(path) => navigation(
            "setRoot",
            NavigateArgs {
                path,
                wait: options.wait,
            },
        ),
        None => Ok(PublicResult::one(text_field(
            &object_response("status", &[])?,
            "rootPath",
        ))),
    }
}
