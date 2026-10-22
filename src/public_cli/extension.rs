use super::*;
use crate::backend::value_name;
use crate::extension_template::image::{
    BANNER_FILE, BANNER_PNG, HOST_LOGO_PNG, banner_svg, host_logo_svg, manifest_name, rasterize,
};
use crate::extension_template::{self, Request, check};
use std::path::Path;

const MODULE_STARTER: &str = include_str!("../module_starter/Module.qml");
const PLACE_WAIT: Duration = Duration::from_secs(5);

const MIN_PNG_WIDTH: u32 = 96;
const MAX_PNG_WIDTH: u32 = 8192;

#[derive(Clone, Debug, Subcommand)]
pub enum ExtensionCommand {
    /// Write a starter Omablade extension (an Omarchy plugin with one blade module) into a new directory.
    Template(ExtensionTemplateArgs),
    /// Check an extension directory, or a module folder with blade.json, and list every problem.
    Check(ExtensionCheckArgs),
    /// Copy a checked extension into the folder Omablade loads extensions from, then rescan.
    Install(ExtensionInstallArgs),
    /// Write the extension banner, outlined so the file needs no fonts installed.
    Image(ExtensionImageArgs),
}

#[derive(Clone, Debug, Args)]
pub struct ExtensionCheckArgs {
    /// Extension directory to check; defaults to the working directory.
    pub directory: Option<String>,
}

#[derive(Clone, Debug, Args)]
pub struct ExtensionInstallArgs {
    /// Extension directory containing manifest.json.
    pub directory: String,
    /// Also place the extension's first module on this blade.
    #[arg(long, value_enum)]
    pub add: Option<Edge>,
    /// Replace an installed copy with the same id.
    #[arg(long)]
    pub replace: bool,
}

#[derive(Clone, Debug, Subcommand)]
pub enum ModuleCommand {
    /// Write a small working module into your modules folder, ready to edit.
    New(ModuleNewArgs),
    /// Reload Omablade's QML so edited modules show their changes; your layout and open folder stay.
    Reload,
}

#[derive(Clone, Debug, Args)]
pub struct ModuleNewArgs {
    /// Module id: lowercase letters, digits and -, for example todo-list.
    pub id: String,
    /// Name shown on the tab; defaults to the id in title case.
    #[arg(long)]
    pub name: Option<String>,
    /// One line for the module picker.
    #[arg(long)]
    pub description: Option<String>,
    /// Also place the module on this blade.
    #[arg(long, value_enum)]
    pub add: Option<Edge>,
    /// Replace an existing module folder with the same id.
    #[arg(long)]
    pub force: bool,
}

#[derive(Clone, Debug, Args)]
pub struct ExtensionImageArgs {
    /// Extension name as shown in the README, for example 'Agent Skills'; defaults to the manifest name without its 'Omablade ' prefix.
    #[arg(long)]
    pub name: Option<String>,
    /// Full subtitle to outline instead of '<NAME> EXTENSION'.
    #[arg(long)]
    pub text: Option<String>,
    /// Manifest read when --name is absent.
    #[arg(long, default_value = "manifest.json")]
    pub manifest: String,
    /// Output directory.
    #[arg(long, default_value = "assets")]
    pub out: String,
    /// Also rasterize the banner with rsvg-convert.
    #[arg(long)]
    pub png: bool,
    /// Also rasterize the plain Omablade logo the host guard shows (assets/omablade-logo.png).
    #[arg(long = "host-logo")]
    pub host_logo: bool,
    /// PNG width in pixels.
    #[arg(long, default_value_t = 1920)]
    pub width: u32,
    /// Print the banner SVG instead of writing files.
    #[arg(long)]
    pub stdout: bool,
}

#[derive(Clone, Debug, Args)]
pub struct ExtensionTemplateArgs {
    /// Omarchy plugin id as publisher.name, for example acme.omablade-weather.
    pub id: String,
    /// Directory to create; defaults to ./<id>, or to Omablade's extension folder with --install.
    pub directory: Option<String>,
    /// Extension name for tabs and the README; defaults to the module id in title case.
    #[arg(long)]
    pub name: Option<String>,
    /// Blade module id; defaults to the plugin name without its omablade- prefix.
    #[arg(long)]
    pub module: Option<String>,
    /// Manifest author and LICENSE holder; defaults to $USER.
    #[arg(long)]
    pub author: Option<String>,
    /// One line for the manifest and the module picker.
    #[arg(long)]
    pub description: Option<String>,
    /// Git URL used by the README install command; defaults to https://github.com/<publisher>/<name>.git.
    #[arg(long)]
    pub repository: Option<String>,
    /// Write into a directory that already has files, replacing only the template's own files.
    #[arg(long)]
    pub force: bool,
    /// Install the new extension into Omablade's extension folder and rescan.
    #[arg(long)]
    pub install: bool,
    /// With --install, also place the module on this blade.
    #[arg(long, value_enum, requires = "install")]
    pub add: Option<Edge>,
}

pub(super) fn extension(action: ExtensionCommand) -> AppResult<PublicResult> {
    match action {
        ExtensionCommand::Template(options) => template(options),
        ExtensionCommand::Check(options) => run_check(options),
        ExtensionCommand::Install(options) => install(options),
        ExtensionCommand::Image(options) => image(options),
    }
}

fn template(options: ExtensionTemplateArgs) -> AppResult<PublicResult> {
    let request = Request {
        id: options.id,
        name: options.name,
        module: options.module,
        author: options.author,
        description: options.description,
        repository: options.repository,
    };
    let scaffold = extension_template::scaffold(&request)?;
    let directory = match (options.directory, options.install) {
        (Some(directory), _) => directory,
        (None, true) => path_string(&crate::lease::native_extension_root().join(&scaffold.id))?,
        (None, false) => scaffold.id.clone(),
    };
    let directory = absolute_directory(&directory)?;
    let files = extension_template::render(&scaffold)?;
    let written = extension_template::write(Path::new(&directory), &files, options.force)?;
    let next = extension_template::next_steps(&scaffold, &directory);
    let mut lines = vec![format!(
        "Created {} ({}) in {directory}",
        scaffold.id, scaffold.name
    )];
    lines.extend(written.iter().map(|path| format!("  {path}")));
    if options.install {
        let installed = install_directory(Path::new(&directory), options.add, true)?;
        lines.push(String::new());
        lines.extend(installed.lines);
        let document = json!({
            "ok": true,
            "id": scaffold.id,
            "name": scaffold.name,
            "module": format!("{}/{}", scaffold.id, scaffold.module),
            "directory": directory,
            "files": written,
            "installed": installed.document,
        });
        return Ok(PublicResult::lines(lines, document));
    }
    lines.push(String::new());
    lines.push("Next:".to_string());
    lines.extend(next.iter().map(|step| format!("  {step}")));
    let document = json!({
        "ok": true,
        "id": scaffold.id,
        "name": scaffold.name,
        "module": format!("{}/{}", scaffold.id, scaffold.module),
        "directory": directory,
        "files": written,
        "next": next,
    });
    Ok(PublicResult::lines(lines, document))
}

fn absolute_directory(value: &str) -> AppResult<String> {
    let path = PathBuf::from(value);
    let absolute = if path.is_absolute() {
        path
    } else {
        std::env::current_dir()?.join(path)
    };
    absolute
        .to_str()
        .map(str::to_string)
        .ok_or_else(|| AppError::invalid("the directory must be valid UTF-8"))
}

fn run_check(options: ExtensionCheckArgs) -> AppResult<PublicResult> {
    let directory = options.directory.unwrap_or_else(|| ".".to_string());
    let directory = absolute_directory(&directory)?;
    let report = check::run(Path::new(&directory))?;
    let mut lines = vec![format!("contract: {} checks ok", report.checks.len())];
    let kind = match report.kind {
        check::Kind::Template => "template",
        check::Kind::Extension => {
            lines.push("host guard and banner checks skipped: not made from the template".into());
            "extension"
        }
        check::Kind::UserModule => "module",
    };
    let document = json!({
        "ok": true,
        "directory": directory,
        "kind": kind,
        "id": report.id,
        "modules": report.modules,
        "checks": report.checks,
    });
    Ok(PublicResult::lines(lines, document))
}

struct Installed {
    lines: Vec<String>,
    document: Value,
}

fn install(options: ExtensionInstallArgs) -> AppResult<PublicResult> {
    let directory = absolute_directory(&options.directory)?;
    let installed = install_directory(Path::new(&directory), options.add, options.replace)?;
    Ok(PublicResult::lines(installed.lines, installed.document))
}

fn install_directory(source: &Path, add: Option<Edge>, replace: bool) -> AppResult<Installed> {
    let report = check::run(source)?;
    if matches!(report.kind, check::Kind::UserModule) {
        return Err(AppError::invalid(
            "this is a module folder (blade.json); copy it into your modules folder or use `omablade module new`",
        ));
    }
    let root = crate::lease::native_extension_root();
    let target = root.join(&report.id);
    let same = std::fs::canonicalize(source).ok() == std::fs::canonicalize(&target).ok();
    if !same {
        if std::fs::symlink_metadata(&target).is_ok() {
            if !replace {
                return Err(AppError::invalid(format!(
                    "{} is already installed at {}; pass --replace to overwrite it",
                    report.id,
                    target.display()
                )));
            }
            if !std::fs::symlink_metadata(&target)?.is_dir() {
                return Err(AppError::invalid(format!(
                    "{} is not a directory; remove it first",
                    target.display()
                )));
            }
        }
        std::fs::create_dir_all(&root)?;
        let staging = root.join(format!(".{}.installing", report.id));
        if std::fs::symlink_metadata(&staging).is_ok() {
            std::fs::remove_dir_all(&staging)?;
        }
        copy_tree(source, &staging).inspect_err(|_| {
            let _ = std::fs::remove_dir_all(&staging);
        })?;
        if std::fs::symlink_metadata(&target).is_ok() {
            std::fs::remove_dir_all(&target)?;
        }
        std::fs::rename(&staging, &target)?;
    }
    let target_text = path_string(&target)?;
    let mut lines = vec![format!("Installed {} in {target_text}", report.id)];
    let module = report
        .modules
        .first()
        .map(|module| format!("{}/{module}", report.id));
    let (rescanned, placed) = rescan_and_place(module.as_deref(), add, &mut lines)?;
    Ok(Installed {
        lines,
        document: json!({
            "ok": true,
            "id": report.id,
            "directory": target_text,
            "modules": report.modules.iter().map(|module| format!("{}/{module}", report.id)).collect::<Vec<_>>(),
            "rescanned": rescanned,
            "placed": placed,
        }),
    })
}

fn copy_tree(source: &Path, target: &Path) -> AppResult<()> {
    std::fs::create_dir(target)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let name = entry.file_name();
        if name == ".git" || name == "target" {
            continue;
        }
        let kind = entry.file_type()?;
        let from = entry.path();
        let to = target.join(&name);
        if kind.is_symlink() {
            return Err(AppError::invalid(format!(
                "{} is a symlink; extensions may not contain links",
                from.display()
            )));
        } else if kind.is_dir() {
            copy_tree(&from, &to)?;
        } else if kind.is_file() {
            std::fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

fn rescan_and_place(
    module: Option<&str>,
    add: Option<Edge>,
    lines: &mut Vec<String>,
) -> AppResult<(bool, Option<String>)> {
    if ipc("rescanBladeModules", &[]).is_err() {
        lines.push("Omablade is not running; the module loads the next time it starts".into());
        if let (Some(edge), Some(module)) = (add, module) {
            lines.push(format!(
                "then place it with: omablade blade add {} {module}",
                value_name(edge)
            ));
        }
        return Ok((false, None));
    }
    lines.push("Rescanned modules".into());
    let Some(module) = module else {
        return Ok((true, None));
    };
    let Some(edge) = add else {
        match placed_edge(module) {
            Some(edge) => lines.push(format!("{module} is on the {edge} blade")),
            None => lines.push(format!("Place it with: omablade blade add right {module}")),
        }
        return Ok((true, None));
    };
    let deadline = Instant::now() + PLACE_WAIT;
    loop {
        if let Some(edge) = placed_edge(module) {
            lines.push(format!("{module} is already on the {edge} blade"));
            return Ok((true, Some(edge)));
        }
        match ipc("addBladeModule", &[value_name(edge), module.to_string()]) {
            Ok(_) => {
                lines.push(format!("Placed {module} on the {} blade", value_name(edge)));
                return Ok((true, Some(value_name(edge))));
            }
            Err(error) if Instant::now() >= deadline => {
                return Err(AppError::command(format!(
                    "installed, but {module} could not be placed: {error}; check `omablade modules`"
                )));
            }
            Err(_) => thread::sleep(Duration::from_millis(200)),
        }
    }
}

fn placed_edge(module: &str) -> Option<String> {
    let layout = response_value(&ipc("blades", &[]).ok()?);
    let blades = layout["blades"].as_object()?;
    blades.iter().find_map(|(edge, blade)| {
        blade["slots"]
            .as_array()?
            .iter()
            .flat_map(|slot| slot["modules"].as_array().into_iter().flatten())
            .any(|entry| entry["module"] == module)
            .then(|| edge.clone())
    })
}

pub(super) fn module(action: ModuleCommand) -> AppResult<PublicResult> {
    match action {
        ModuleCommand::New(options) => module_new(options),
        ModuleCommand::Reload => module_reload(),
    }
}

fn module_reload() -> AppResult<PublicResult> {
    let status = response_value(&ipc("status", &[])?);
    if status["operationBusy"] == true {
        return Err(AppError::command(
            "a file operation is running; reload when it finishes",
        ));
    }
    ipc_on("omablade.native", "reloadModules", &[]).map_err(|_| {
        AppError::command("reloading needs the native Omablade app; restart Omablade instead")
    })?;
    let deadline = Instant::now() + PLACE_WAIT * 2;
    thread::sleep(Duration::from_millis(500));
    while ipc("status", &[]).is_err() {
        if Instant::now() >= deadline {
            return Err(AppError::command(
                "Omablade did not answer after reloading; check its log",
            ));
        }
        thread::sleep(Duration::from_millis(200));
    }
    Ok(PublicResult::lines(
        vec!["Reloaded; edited modules now show their changes".into()],
        json!({"ok": true, "reloaded": true}),
    ))
}

fn module_new(options: ModuleNewArgs) -> AppResult<PublicResult> {
    let id = options.id.trim();
    let valid = (1..=64).contains(&id.len())
        && id
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        && !id.starts_with('-');
    if !valid {
        return Err(AppError::invalid(
            "the module id must be 1 to 64 lowercase letters, digits and -, for example todo-list",
        ));
    }
    let name = options
        .name
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| {
            id.split('-')
                .filter(|part| !part.is_empty())
                .map(|part| {
                    let mut chars = part.chars();
                    chars.next().map_or_else(String::new, |first| {
                        first.to_uppercase().chain(chars).collect()
                    })
                })
                .collect::<Vec<_>>()
                .join(" ")
        });
    if name.chars().count() > 64 || name.chars().any(char::is_control) {
        return Err(AppError::invalid(
            "the name must be at most 64 printable characters",
        ));
    }
    let description = options
        .description
        .unwrap_or_else(|| format!("{name}, a module of my own"));
    if description.chars().count() > 160 || description.chars().any(char::is_control) {
        return Err(AppError::invalid(
            "the description must be at most 160 printable characters",
        ));
    }
    let directory = crate::lease::native_config_root().join("modules").join(id);
    if std::fs::symlink_metadata(&directory).is_ok() && !options.force {
        return Err(AppError::invalid(format!(
            "{} already exists; pass --force to overwrite its blade.json and Module.qml",
            directory.display()
        )));
    }
    std::fs::create_dir_all(&directory)?;
    let module_file = directory.join("Module.qml");
    let quoted = |value: &str| -> AppResult<String> {
        let encoded = serde_json::to_string(value)?;
        Ok(encoded[1..encoded.len() - 1].to_string())
    };
    let source = MODULE_STARTER
        .replace("{{NAME}}", &quoted(&name)?)
        .replace("{{FILE}}", &quoted(&path_string(&module_file)?)?);
    let definition = json!({
        "id": id,
        "name": name,
        "glyph": "󰏗",
        "description": description,
        "entry": "Module.qml",
        "hostContract": 1,
        "singleton": true,
        "minHeight": 120,
    });
    std::fs::write(
        directory.join("blade.json"),
        format!("{}\n", serde_json::to_string_pretty(&definition)?),
    )?;
    std::fs::write(&module_file, source)?;
    let directory_text = path_string(&directory)?;
    let mut lines = vec![
        format!("Created module {id} ({name}) in {directory_text}"),
        format!("  {directory_text}/blade.json"),
        format!("  {}", path_string(&module_file)?),
    ];
    let (rescanned, placed) = rescan_and_place(Some(id), options.add, &mut lines)?;
    lines.push("Edit Module.qml, then run `omablade module reload` to see your changes".into());
    lines.push(format!(
        "`omablade extension check {directory_text}` lists any problems; EXTENSIONS.md lists what context offers"
    ));
    let document = json!({
        "ok": true,
        "id": id,
        "name": name,
        "directory": directory_text,
        "files": ["blade.json", "Module.qml"],
        "rescanned": rescanned,
        "placed": placed,
    });
    Ok(PublicResult::lines(lines, document))
}

fn image(options: ExtensionImageArgs) -> AppResult<PublicResult> {
    let name = match (&options.name, &options.text) {
        (Some(name), _) => name.clone(),
        (None, Some(text)) => {
            manifest_name(Path::new(&options.manifest)).unwrap_or_else(|_| text.clone())
        }
        (None, None) => manifest_name(Path::new(&options.manifest))?,
    };
    let svg = banner_svg(&name, options.text.as_deref())?;
    if options.stdout {
        return Ok(PublicResult::lines(
            vec![svg.trim_end_matches('\n').to_string()],
            json!({"ok": true, "svg": svg}),
        ));
    }
    let width = options.width.clamp(MIN_PNG_WIDTH, MAX_PNG_WIDTH);
    let out = PathBuf::from(absolute_directory(&options.out)?);
    std::fs::create_dir_all(&out)?;
    let banner = out.join(BANNER_FILE);
    std::fs::write(&banner, svg.as_bytes())?;
    let mut written = vec![path_string(&banner)?];
    if options.png {
        let target = out.join(BANNER_PNG);
        rasterize(&svg, &target, width)?;
        written.push(path_string(&target)?);
    }
    if options.host_logo {
        let target = out.join(HOST_LOGO_PNG);
        rasterize(&host_logo_svg(), &target, width)?;
        written.push(path_string(&target)?);
    }
    let document = json!({"ok": true, "files": written});
    Ok(PublicResult::lines(written, document))
}

fn path_string(path: &Path) -> AppResult<String> {
    path.to_str()
        .map(str::to_string)
        .ok_or_else(|| AppError::invalid("the output path must be valid UTF-8"))
}
