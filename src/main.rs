use resolve_path::PathResolveExt;

use std::{
    path::{Path, PathBuf},
    process::Command,
};

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ni")]
#[command(about = "A small nix convenience wrapper", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Rebuilds the Nix environment
    Rebuild {
        /// Specify the flake path to rebuild
        #[arg(short, long, env = "NIXOS_CONFIG")]
        path: PathBuf,
        #[arg(short, long)]
        label: Option<String>,
        message: String,
    },
    /// Updates the Nix environment
    Update {
        /// Specify the flake path to update
        #[arg(short, long, env = "NIXOS_CONFIG")]
        path: PathBuf,
    },
    /// Cleans up the Nix environment
    Clean,
    /// Audits the Nix environment for issues
    Audit { key: String },
}

fn main() {
    let cli = Cli::parse();

    match &cli.command {
        Commands::Rebuild {
            path,
            label,
            message,
        } => {
            rebuild(path, label.as_deref(), message).unwrap();
        }
        Commands::Update { path } => {
            update(path).unwrap();
        }
        Commands::Audit { key } => {
            audit(key).unwrap();
        }
        Commands::Clean {} => clean().unwrap(),
    }
}

fn rebuild(nixos_path: &Path, label: Option<&str>, message: &str) -> anyhow::Result<()> {
    let nixos_path = nixos_path.resolve();
    let label = label.unwrap_or(message);
    let sanitized_label = sanitize_label(label);

    println!("path: {:?}", nixos_path);
    println!("message: {:?}", message);
    println!("label: {:?}", sanitized_label);

    let mut command = script_command("rebuild");
    command
        .arg(nixos_path.as_ref())
        .arg(message)
        .arg(sanitized_label)
        .status()?;

    Ok(())
}

fn update(nixos_path: &Path) -> anyhow::Result<()> {
    let nixos_path = nixos_path.resolve();
    println!("path: {:?}", nixos_path);

    let mut command = script_command("update");
    command.arg(nixos_path.as_ref()).status()?;

    rebuild(nixos_path.as_ref(), None, "update")?;

    Ok(())
}

fn clean() -> anyhow::Result<()> {
    let mut command = script_command("clean");
    command.status()?;

    Ok(())
}

fn audit(key: &str) -> anyhow::Result<()> {
    let mut command = script_command("audit");
    command.arg(key).status()?;

    Ok(())
}

fn sanitize_label(input: &str) -> String {
    input
        .chars()
        .filter_map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | ':' | '_' | '.' | '-' => Some(c),
            ' ' => Some('_'),
            _ => None,
        })
        .collect()
}

fn script_command(name: &str) -> Command {
    let script_path = std::option_env!("MY_SCRIPT_PATH")
        .map(PathBuf::from)
        .unwrap_or(PathBuf::from(std::env!("CARGO_MANIFEST_DIR")).join("scripts"));
    let script_path = script_path.join(name).with_extension("sh");

    Command::new(script_path)
}
